# Stage 1: Build SPA
FROM node:22-alpine AS spa
ARG APP_VERSION=0.0.0
WORKDIR /app
COPY client/web/package*.json ./
RUN npm ci
COPY client/web/ ./
RUN VITE_APP_VERSION=$APP_VERSION npm run build

# npm third-party license manifests (production deps only — devDeps aren't
# shipped in the final image). Generated here so the Dockerfile doesn't
# depend on `build.sh` having been run first.
RUN mkdir -p /licenses/npm \
    && npx --yes license-checker --production --json --out /licenses/npm/licenses.json \
    && npx --yes license-checker --production --markdown --out /licenses/npm/licenses.md

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

# NuGet third-party license manifests. Restoring the local tool gives us
# dotnet-project-licenses at the version pinned in .config/dotnet-tools.json
# so the output is reproducible between host builds and container builds.
COPY .config/dotnet-tools.json .config/dotnet-tools.json
RUN dotnet tool restore \
    && mkdir -p /licenses/nuget \
    && dotnet dotnet-project-licenses --input src --include-transitive --unique --json --output-directory /licenses/nuget \
    && dotnet dotnet-project-licenses --input src --include-transitive --unique --md   --output-directory /licenses/nuget

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

# Third-party license manifests — same content as publish/licenses/ in
# archive releases. Satisfies the attribution clauses that MIT / BSD /
# Apache / MPL dependencies require when the image is redistributed.
COPY --from=build /licenses /app/licenses
COPY --from=spa   /licenses/npm /app/licenses/npm
COPY LICENSE /app/LICENSE
RUN printf '# Third-party licenses\n\nThis directory lists every third-party dependency baked into this image.\nIt is machine-generated at build time and exists to satisfy the attribution\nrequirements of MIT / BSD / Apache / MPL / etc. dependencies.\n\n- `nuget/licenses.md` / `nuget/licenses.json` \xe2\x80\x94 NuGet packages\n  (transitive included, deduped) pulled in by the .NET server.\n- `npm/licenses.md` / `npm/licenses.json` \xe2\x80\x94 npm production\n  dependencies pulled in by the web client.\n\nPsTotp itself is licensed under Apache 2.0 \xe2\x80\x94 see `/app/LICENSE`.\n' > /app/licenses/README.md

RUN mkdir /data && chown pstotp:pstotp /data
VOLUME /data

EXPOSE 5000
ENV ASPNETCORE_ENVIRONMENT=Production
ENV PSTOTP_DATA=/data
ENV OpenBrowser=false

USER pstotp
ENTRYPOINT ["dotnet", "PsTotp.Server.Api.dll"]
