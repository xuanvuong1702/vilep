class UserProfile {
  final String id;
  final String phone;
  final String nickname;
  final String avatarKey;
  final String bio;
  final int kycTier;
  final bool ageVerified;
  final int trustScore;
  final String role;

  const UserProfile({
    required this.id,
    required this.phone,
    required this.nickname,
    required this.avatarKey,
    required this.bio,
    required this.kycTier,
    required this.ageVerified,
    required this.trustScore,
    required this.role,
  });

  bool get isAdmin => role == 'admin';
  bool get canCreateModeA => kycTier >= 1;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        phone: json['phone'] as String? ?? '',
        nickname: json['nickname'] as String? ?? '',
        avatarKey: json['avatarKey'] as String? ?? 'wallet-1',
        bio: json['bio'] as String? ?? '',
        kycTier: (json['kycTier'] as num?)?.toInt() ?? 0,
        ageVerified: json['ageVerified'] as bool? ?? false,
        trustScore: (json['trustScore'] as num?)?.toInt() ?? 100,
        role: json['role'] as String? ?? 'user',
      );

  UserProfile copyWith({String? nickname, String? avatarKey, String? bio, int? kycTier, bool? ageVerified}) =>
      UserProfile(
        id: id,
        phone: phone,
        nickname: nickname ?? this.nickname,
        avatarKey: avatarKey ?? this.avatarKey,
        bio: bio ?? this.bio,
        kycTier: kycTier ?? this.kycTier,
        ageVerified: ageVerified ?? this.ageVerified,
        trustScore: trustScore,
        role: role,
      );
}

class UserBrief {
  final String id;
  final String nickname;
  final String avatarKey;

  const UserBrief({required this.id, required this.nickname, required this.avatarKey});

  factory UserBrief.fromJson(Map<String, dynamic> json) => UserBrief(
        id: json['id'] as String? ?? '',
        nickname: json['nickname'] as String? ?? '',
        avatarKey: json['avatarKey'] as String? ?? 'wallet-1',
      );
}

class CaseSummary {
  final String id;
  final String code;
  final String title;
  final String category;
  final String payoutMode;
  final String state;
  final int percent;
  final int targetAmount;
  final int raisedAmount;
  final int contributorCount;
  final DateTime? deadline;
  final int daysLeft;
  final DateTime? createdAt;
  final UserBrief? debtor;
  final bool creditorConfirmed;
  final String creditorName;
  final String label;
  final String coverEmoji;
  final String coverColor;
  final bool isMine;
  final bool canContribute;

  const CaseSummary({
    required this.id,
    required this.code,
    required this.title,
    required this.category,
    required this.payoutMode,
    required this.state,
    required this.percent,
    required this.targetAmount,
    required this.raisedAmount,
    required this.contributorCount,
    required this.deadline,
    required this.daysLeft,
    required this.createdAt,
    required this.debtor,
    required this.creditorConfirmed,
    required this.creditorName,
    required this.label,
    required this.coverEmoji,
    required this.coverColor,
    required this.isMine,
    required this.canContribute,
  });

  bool get isModeA => payoutMode == 'creditor';

  factory CaseSummary.fromJson(Map<String, dynamic> json) => CaseSummary(
        id: json['id'] as String,
        code: json['code'] as String? ?? '',
        title: json['title'] as String? ?? '',
        category: json['category'] as String? ?? 'khac',
        payoutMode: json['payoutMode'] as String? ?? 'creditor',
        state: json['state'] as String? ?? 'funding',
        percent: (json['percent'] as num?)?.toInt() ?? 0,
        targetAmount: (json['targetAmount'] as num?)?.toInt() ?? 0,
        raisedAmount: (json['raisedAmount'] as num?)?.toInt() ?? 0,
        contributorCount: (json['contributorCount'] as num?)?.toInt() ?? 0,
        deadline: _date(json['deadline']),
        daysLeft: (json['daysLeft'] as num?)?.toInt() ?? 0,
        createdAt: _date(json['createdAt']),
        debtor: json['debtor'] == null ? null : UserBrief.fromJson(json['debtor'] as Map<String, dynamic>),
        creditorConfirmed: json['creditorConfirmed'] as bool? ?? false,
        creditorName: json['creditorName'] as String? ?? '',
        label: json['label'] as String? ?? '',
        coverEmoji: json['coverEmoji'] as String? ?? '👛',
        coverColor: json['coverColor'] as String? ?? '#D0F4DE',
        isMine: json['isMine'] as bool? ?? false,
        canContribute: json['canContribute'] as bool? ?? false,
      );
}

class Contributor {
  final String name;
  final String avatarKey;
  final int amount;
  final String? message;
  final String? sticker;
  final DateTime? createdAt;
  final bool isLastToClose;

  const Contributor({
    required this.name,
    required this.avatarKey,
    required this.amount,
    required this.message,
    required this.sticker,
    required this.createdAt,
    required this.isLastToClose,
  });

  factory Contributor.fromJson(Map<String, dynamic> json) => Contributor(
        name: json['name'] as String? ?? 'Người dùng',
        avatarKey: json['avatarKey'] as String? ?? 'wallet-1',
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        message: json['message'] as String?,
        sticker: json['sticker'] as String?,
        createdAt: _date(json['createdAt']),
        isLastToClose: json['isLastToClose'] as bool? ?? false,
      );
}

class CaseDetail {
  final CaseSummary summary;
  final String story;
  final int debtAmount;
  final int remaining;
  final int minContribution;
  final int tipSuggestAmount;
  final String moneyDestination;
  final List<Contributor> contributors;
  final List<String> nextStates;
  final String? certificateCode;
  final DateTime? paidAt;
  final String? payoutReceiptRef;
  final String creditorBankMasked;

  const CaseDetail({
    required this.summary,
    required this.story,
    required this.debtAmount,
    required this.remaining,
    required this.minContribution,
    required this.tipSuggestAmount,
    required this.moneyDestination,
    required this.contributors,
    required this.nextStates,
    required this.certificateCode,
    required this.paidAt,
    required this.payoutReceiptRef,
    required this.creditorBankMasked,
  });

  bool get isClosed => summary.state == 'closed' || summary.state == 'refunded';
  bool get isPaid => summary.state == 'paid' || summary.state == 'closed';

  factory CaseDetail.fromJson(Map<String, dynamic> json) => CaseDetail(
        summary: CaseSummary.fromJson(json),
        story: json['story'] as String? ?? '',
        debtAmount: (json['debtAmount'] as num?)?.toInt() ?? 0,
        remaining: (json['remaining'] as num?)?.toInt() ?? 0,
        minContribution: (json['minContribution'] as num?)?.toInt() ?? 10000,
        tipSuggestAmount: (json['tipSuggestAmount'] as num?)?.toInt() ?? 10000,
        moneyDestination: json['moneyDestination'] as String? ?? '',
        contributors: ((json['contributors'] as List?) ?? const [])
            .map((e) => Contributor.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextStates: ((json['nextStates'] as List?) ?? const []).map((e) => e.toString()).toList(),
        certificateCode: json['certificateCode'] as String?,
        paidAt: _date(json['paidAt']),
        payoutReceiptRef: json['payoutReceiptRef'] as String?,
        creditorBankMasked: json['creditorBankMasked'] as String? ?? '',
      );
}

class FeedPage {
  final List<CaseSummary> items;
  final String? nextCursor;

  const FeedPage({required this.items, this.nextCursor});

  factory FeedPage.fromJson(Map<String, dynamic> json) => FeedPage(
        items: ((json['items'] as List?) ?? const [])
            .map((e) => CaseSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextCursor: json['nextCursor'] as String?,
      );
}

class ContributionCreated {
  final String contributionId;
  final int amount;
  final int tipAmount;
  final int feeAmount;
  final int total;
  final String checkoutUrl;
  final String qrPayload;
  final String provider;

  const ContributionCreated({
    required this.contributionId,
    required this.amount,
    required this.tipAmount,
    required this.feeAmount,
    required this.total,
    required this.checkoutUrl,
    required this.qrPayload,
    required this.provider,
  });

  factory ContributionCreated.fromJson(Map<String, dynamic> json) {
    final created = json['created'] as Map<String, dynamic>? ?? json;
    return ContributionCreated(
      contributionId: created['contributionId'] as String,
      amount: (created['amount'] as num?)?.toInt() ?? 0,
      tipAmount: (created['tipAmount'] as num?)?.toInt() ?? 0,
      feeAmount: (created['feeAmount'] as num?)?.toInt() ?? 0,
      total: (created['total'] as num?)?.toInt() ?? 0,
      checkoutUrl: created['checkoutUrl'] as String? ?? '',
      qrPayload: created['qrPayload'] as String? ?? '',
      provider: created['provider'] as String? ?? 'mock',
    );
  }
}

class NotificationItem {
  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime? createdAt;
  final DateTime? readAt;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.readAt,
  });

  bool get unread => readAt == null;

  factory NotificationItem.fromJson(Map<String, dynamic> json) => NotificationItem(
        id: json['id'] as String,
        type: json['type'] as String? ?? 'info',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        createdAt: _date(json['createdAt']),
        readAt: _date(json['readAt']),
      );
}

class DebtTemplate {
  final String key;
  final String category;
  final String emoji;
  final String title;
  final int amount;
  final String story;

  const DebtTemplate({
    required this.key,
    required this.category,
    required this.emoji,
    required this.title,
    required this.amount,
    required this.story,
  });

  factory DebtTemplate.fromJson(Map<String, dynamic> json) => DebtTemplate(
        key: json['key'] as String? ?? '',
        category: json['category'] as String? ?? 'khac',
        emoji: json['emoji'] as String? ?? '👛',
        title: json['title'] as String? ?? '',
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        story: json['story'] as String? ?? '',
      );
}

class MetaConfig {
  final int minContribution;
  final int funModeAMin;
  final int funModeAMax;
  final int funModeBMax;
  final List<DebtTemplate> templates;

  const MetaConfig({
    required this.minContribution,
    required this.funModeAMin,
    required this.funModeAMax,
    required this.funModeBMax,
    required this.templates,
  });

  factory MetaConfig.fromJson(Map<String, dynamic> json, List<DebtTemplate> templates) => MetaConfig(
        minContribution: int.tryParse('${json['minContribution']}') ?? 10000,
        funModeAMin: int.tryParse('${json['funModeAMin']}') ?? 20000,
        funModeAMax: int.tryParse('${json['funModeAMax']}') ?? 500000,
        funModeBMax: int.tryParse('${json['funModeBMax']}') ?? 300000,
        templates: templates,
      );
}

class CreditorInvite {
  final bool expired;
  final bool confirmed;
  final String creditorName;
  final String caseTitle;
  final String story;
  final String debtorName;
  final int amount;
  final int debtAmount;
  final String caseCode;
  final String caseId;
  final String token;

  const CreditorInvite({
    required this.expired,
    required this.confirmed,
    required this.creditorName,
    required this.caseTitle,
    required this.story,
    required this.debtorName,
    required this.amount,
    required this.debtAmount,
    required this.caseCode,
    required this.caseId,
    required this.token,
  });

  factory CreditorInvite.fromJson(Map<String, dynamic> json) => CreditorInvite(
        expired: json['expired'] as bool? ?? false,
        confirmed: json['confirmed'] as bool? ?? false,
        creditorName: json['creditorName'] as String? ?? '',
        caseTitle: json['caseTitle'] as String? ?? '',
        story: json['story'] as String? ?? '',
        debtorName: json['debtorName'] as String? ?? '',
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        debtAmount: (json['debtAmount'] as num?)?.toInt() ?? 0,
        caseCode: json['caseCode'] as String? ?? '',
        caseId: json['caseId'] as String? ?? '',
        token: json['token'] as String? ?? '',
      );
}

DateTime? _date(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
