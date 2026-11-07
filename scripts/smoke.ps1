# Ví Lép — end-to-end smoke test (mode A happy path + duplicate webhook + invariants)
# Usage: pwsh ./scripts/smoke.ps1 [-BaseUrl http://127.0.0.1:5080]

param([string]$BaseUrl = "http://127.0.0.1:5080")

$ErrorActionPreference = "Stop"
$script:passed = 0
$script:failed = 0

function Step($name) { Write-Host "`n== $name" -ForegroundColor Cyan }
function Check($condition, $message) {
    if ($condition) { $script:passed++; Write-Host "  PASS $message" -ForegroundColor Green }
    else { $script:failed++; Write-Host "  FAIL $message" -ForegroundColor Red }
}

function Post($path, $body, $token, [hashtable]$extraHeaders) {
    $headers = @{}
    if ($token) { $headers["Authorization"] = "Bearer $token" }
    if ($extraHeaders) { foreach ($k in $extraHeaders.Keys) { $headers[$k] = $extraHeaders[$k] } }
    $json = if ($body -is [string]) { $body } else { $body | ConvertTo-Json -Depth 8 -Compress }
    Invoke-RestMethod -Uri "$BaseUrl$path" -Method Post -Headers $headers -ContentType "application/json; charset=utf-8" -Body $json
}

function Get-Api($path, $token) {
    $headers = @{}
    if ($token) { $headers["Authorization"] = "Bearer $token" }
    Invoke-RestMethod -Uri "$BaseUrl$path" -Headers $headers
}

function Login($phone) {
    $otp = Post "/api/v1/auth/otp/request" @{ phone = $phone }
    $verify = Post "/api/v1/auth/otp/verify" @{ phone = $phone; code = $otp.data.devCode }
    return $verify.data
}

Step "Health"
$health = Invoke-RestMethod -Uri "$BaseUrl/health"
Check ($health.ok -eq $true) "API trả về ok"

Step "Đăng nhập OTP (user mới)"
$newPhone = "0909" + (Get-Random -Minimum 100000 -Maximum 999999)
$debtor = Login $newPhone
Check ($debtor.accessToken.Length -gt 20) "Nhận access token"
Check ($debtor.user.phone -eq $newPhone) "Đúng số điện thoại"

Step "KYC bậc 1"
$kyc = Post "/api/v1/me/kyc" @{ tier = 1; fullName = "Nguyen Van Test"; idNumber = "0792000" + (Get-Random -Minimum 10000 -Maximum 99999); dob = "2000-01-01" } $debtor.accessToken
Check ($kyc.data.tier -ge 1) "KYC bậc 1 đã duyệt (mock eKYC)"
Check ($kyc.data.ageVerified -eq $true) "Xác nhận 18+"

Step "Tạo case nháp"
$case = Post "/api/v1/my/cases" @{
    title = "Nợ trà sữa tự động test"
    story = "Đây là case do script smoke test tạo ra để kiểm tra toàn bộ luồng tiền từ đóng góp tới payout."
    category = "tra-sua"
    debtAmount = 60000
    targetAmount = 60000
    displayMode = "nickname"
    templateKey = "tra-sua"
} $debtor.accessToken
Check ($case.data.state -eq "draft") "Case ở trạng thái draft"
$caseId = $case.data.id

Step "Mời chủ nợ + chủ nợ xác nhận"
$invite = Post "/api/v1/my/cases/$caseId/invite-creditor" @{ name = "Cô Bán Trà Sữa"; phone = "0911222333" } $debtor.accessToken
Check ($invite.data.inviteUrl -like "*/creditor/invite/*") "Sinh link mời chủ nợ"
$token = $invite.data.token

$inviteView = Get-Api "/api/v1/creditor/invite/$token"
Check ($inviteView.data.caseTitle -eq $case.data.title -or $inviteView.data.expired -eq $false) "Chủ nợ mở link xem được case"

$confirm = Post "/api/v1/creditor/invite/$token/confirm" @{ accountName = "Cô Bán Trà Sữa"; bankCode = "VCB"; accountNo = "0123456789" }
Check ($confirm.data.confirmed -eq $true) "Chủ nợ xác nhận khoản nợ"
Check ($confirm.data.state -eq "funding") "Case tự chuyển sang funding"

$detail0 = Get-Api "/api/v1/cases/$caseId"
Check ($detail0.data.label -eq "Chủ nợ đã xác nhận") "Nhãn chế độ A hiển thị đúng"
Check ($detail0.data.moneyDestination -like "*chủ nợ*") "Khối 'Tiền sẽ về đâu' đúng chế độ A"

Step "Đóng góp (2 người, chốt hạ cuối)"
$lan = Login "0900000002"
$hung = Login "0900000004"

$c1 = Post "/api/v1/cases/$caseId/contributions" @{ amount = 30000; tipAmount = 5000; anonymous = $false; message = "Cứu ví lép!" } $lan.accessToken @{ "Idempotency-Key" = [guid]::NewGuid().ToString() }
Check ($c1.data.created.amount -eq 30000) "Tạo khoản góp 30k + tip 5k"
Check ($c1.data.created.total -eq 35000) "Tổng thanh toán = góp + tip + phí"

$pay1 = Post "/api/v1/dev/pay/$($c1.data.created.contributionId)" @{} $lan.accessToken
Check ($pay1.data.credited -eq 30000) "Webhook ghi nhận 30k vào escrow"

$dup1 = Post "/api/v1/dev/pay/$($c1.data.created.contributionId)" @{} $lan.accessToken
Check ($dup1.data.duplicate -eq $true -and $dup1.data.credited -eq 0) "Webhook lặp không ghi nhận lần 2"

$detail1 = Get-Api "/api/v1/cases/$caseId"
Check ($detail1.data.raisedAmount -eq 30000) "Case raised = 30k (không nhân đôi)"

$c2 = Post "/api/v1/cases/$caseId/contributions" @{ amount = 30000; tipAmount = 0; anonymous = $true; message = "Chốt hạ!" } $hung.accessToken @{ "Idempotency-Key" = [guid]::NewGuid().ToString() }
$pay2 = Post "/api/v1/dev/pay/$($c2.data.created.contributionId)" @{} $hung.accessToken
Check ($pay2.data.credited -eq 30000) "Người thứ 2 chốt hạ 30k"
Check ($pay2.data.caseState -eq "paid" -or $pay2.data.caseState -eq "closed") "Case tự funded -> payout -> paid (state=$($pay2.data.caseState))"

Step "Kiểm tra chi tiết sau khi đủ tiền"
$detail2 = Get-Api "/api/v1/cases/$caseId"
Check ($detail2.data.percent -eq 100) "Tiến độ 100%"
Check ($detail2.data.raisedAmount -eq 60000) "Không vượt mục tiêu"
$lastToClose = $detail2.data.contributors | Where-Object { $_.isLastToClose }
Check (@($lastToClose).Count -eq 1) "Chỉ một người là 'Người chốt hạ'"
Check ($detail2.data.contributors[0].message.Length -gt 0) "Lời nhắn hiển thị trên tường người cứu nợ"

Step "Chủ nợ xác nhận đã nhận tiền"
$received = Post "/api/v1/creditor/$token/received" @{}
Check ($received.data.state -eq "closed") "Case chuyển closed"
Check ($received.data.certificate -like "VL-*") "Sinh mã giấy chứng nhận"

$detail3 = Get-Api "/api/v1/cases/$caseId"
Check ($detail3.data.state -eq "closed") "Chi tiết case closed"
Check ($detail3.data.certificateCode -ne $null) "Có số chứng nhận"
Check ($detail3.data.payoutReceiptRef -ne $null) "Có mã chứng từ payout"

Step "Chặn lỗi nghiệp vụ"
$lan2 = Login "0900000005"
try {
    Post "/api/v1/cases/$caseId/contributions" @{ amount = 10000; tipAmount = 0 } $lan2.accessToken @{ "Idempotency-Key" = [guid]::NewGuid().ToString() } | Out-Null
    Check $false "Đóng góp vào case đã đóng phải bị chặn"
} catch { Check ($_.Exception.Response.StatusCode.value__ -ge 400) "Đóng góp vào case đã đóng bị chặn" }

$ownCase = Get-Api "/api/v1/cases?tab=newest&limit=50"
$own = $ownCase.data.items | Where-Object { $_.id -eq $caseId }
try {
    Post "/api/v1/cases/$caseId/contributions" @{ amount = 10000; tipAmount = 0 } $debtor.accessToken @{ "Idempotency-Key" = [guid]::NewGuid().ToString() } | Out-Null
    Check $false "Tự góp vào case của mình phải bị chặn"
} catch { Check ($_.Exception.Response.StatusCode.value__ -eq 403) "Chặn tự đóng góp vào case của mình (403)" }

Step "Admin: đối soát & invariant"
$admin = Login "0900000003"
Check ($admin.user.role -eq "admin") "Đăng nhập admin"
$inv = Get-Api "/api/v1/admin/invariants" $admin.accessToken
Check ($inv.data.ok -eq $true) "Invariant ledger toàn hệ thống cân bằng ($($inv.data.checkedCases) case)"
$stats = Get-Api "/api/v1/admin/stats" $admin.accessToken
Check ($stats.data.contributions -gt 0) "Dashboard có số liệu"

$audit = Get-Api "/api/v1/admin/cases/$caseId/audit" $admin.accessToken
Check ($audit.data.items.Count -ge 3) "Audit log ghi mọi chuyển trạng thái"

$ledger = Get-Api "/api/v1/admin/cases/$caseId/ledger" $admin.accessToken
Check ($ledger.data.escrowBalance -eq 0) "Escrow case = 0 sau khi payout"

Step "Feed tabs & share card"
foreach ($tab in @("need", "almost", "newest")) {
    $feed = Get-Api "/api/v1/cases?tab=$tab&limit=10"
    Check ($feed.ok -eq $true) "Tab '$tab' trả dữ liệu ($(@($feed.data.items).Count) case)"
}
$share = Get-Api "/api/v1/share/trasua01"
Check ($share.data.percent -gt 0) "Share info có tiến độ"
$svg = Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/api/v1/cases/$($share.data.caseId)/share-card.svg"
Check ($svg.Content -like "*<svg*") "Share card SVG sinh được"

Write-Host "`n=====================================" -ForegroundColor Yellow
Write-Host "PASS: $script:passed   FAIL: $script:failed" -ForegroundColor $(if ($script:failed -eq 0) { "Green" } else { "Red" })
Write-Host "=====================================" -ForegroundColor Yellow
if ($script:failed -gt 0) { exit 1 }
