# Build stage
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY apps/api/Vilep.Api/Vilep.Api.csproj apps/api/Vilep.Api/
RUN dotnet restore apps/api/Vilep.Api/Vilep.Api.csproj

COPY apps/api/ apps/api/
RUN dotnet publish apps/api/Vilep.Api/Vilep.Api.csproj -c Release -o /app --no-restore

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_URLS=http://+:8080 \
    ASPNETCORE_ENVIRONMENT=Production \
    DOTNET_RUNNING_IN_CONTAINER=true
EXPOSE 8080
RUN mkdir -p /app/App_Data && chown -R app:app /app/App_Data
USER app
ENTRYPOINT ["dotnet", "Vilep.Api.dll"]
