FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app

# Copy pubspec files first for layer caching
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

# Copy source
COPY . .

# Enable web platform (creates web/ stubs if missing, no-op if already present)
RUN flutter create --platforms web . 2>/dev/null || true

# Build for web.
# API_BASE_URL is intentionally NOT hardcoded here.
# On web the app reads the origin from the browser at runtime (Uri.base),
# so it works from localhost, LAN IP, or any hostname without rebuilding.
# Pass --build-arg API_BASE_URL=https://yourserver.com only for production.
ARG API_BASE_URL
RUN flutter build web --release ${API_BASE_URL:+--dart-define=API_BASE_URL=$API_BASE_URL}

# Serve with nginx
FROM nginx:alpine

COPY --from=builder /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
