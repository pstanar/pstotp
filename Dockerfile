# Stage 1: Build SPA
FROM node:22-alpine AS spa
ARG APP_VERSION=0.0.0
WORKDIR /app
COPY client/web/package*.json ./
RUN npm ci
COPY client/web/ ./
RUN VITE_APP_VERSION=$APP_VERSION npm run build

# Stage 2: Build .NET backend
FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src

# Copy project files for NuGet restore (layer cache)
COPY nuget.config Directory.Build.props ./
COPY src/Server.Api/PsTotp.Server.Api.csproj                                           src/Server.Api/
COPY src/Server.Application/PsTotp.Server.Application.csproj                           src/Server.Application/
COPY src/Server.Domain/PsTotp.Server.Domain.csproj                                     src/Server.Domain/
COPY src/Server.Infrastructure/PsTotp.Server.Infrastructure.csproj                     src/Server.Infrastructure/
COPY src/Server.Infrastructure.Postgres/PsTotp.Server.Infrastructure.Postgres.csproj   src/Server.Infrastructure.Postgres/
COPY src/Server.Infrastructure.SqlServer/PsTotp.Server.Infrastructure.SqlServer.csproj src/Server.Infrastructure.SqlServer/
COPY src/Server.Infrastructure.Sqlite/PsTotp.Server.Infrastructure.Sqlite.csproj       src/Server.Infrastructure.Sqlite/
COPY src/Server.Infrastructure.MySql/PsTotp.Server.Infrastructure.MySql.csproj         src/Server.Infrastructure.MySql/
RUN dotnet restore src/Server.Api/PsTotp.Server.Api.csproj

# Copy source and publish
COPY src/ src/
RUN dotnet publish src/Server.Api/PsTotp.Server.Api.csproj \
    -c Release --no-restore -p:SkipSpa=true -o /app/publish

# Stage 3: Runtime
FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine
RUN apk add --no-cache icu-libs
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false

RUN addgroup -S pstotp && adduser -S pstotp -G pstotp
WORKDIR /app

COPY --from=build /app/publish .
COPY --from=spa /app/dist wwwroot/

RUN mkdir /data && chown pstotp:pstotp /data
VOLUME /data

EXPOSE 5000
ENV ASPNETCORE_ENVIRONMENT=Production
ENV PSTOTP_DATA=/data
ENV OpenBrowser=false

USER pstotp
ENTRYPOINT ["dotnet", "PsTotp.Server.Api.dll"]
