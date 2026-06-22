# syntax=docker/dockerfile:1
# ============================================
# Stage 1: Build Flutter Web
# ============================================
FROM ghcr.io/cirruslabs/flutter:stable AS build-stage

WORKDIR /app

# Copy only dependency files first (for better layer caching)
COPY pubspec.yaml pubspec.lock ./

# Download pub dependencies (cached across rebuilds)
RUN --mount=type=cache,target=/root/.pub-cache \
    flutter pub get

# Copy only the source code needed for web build
COPY lib/ ./lib/
COPY web/ ./web/
COPY analysis_options.yaml ./

# Build web release — no --dart-define needed; the app uses relative URLs
# (same-origin via nginx /api/ proxy) so it works from any host automatically.
RUN --mount=type=cache,target=/root/.pub-cache \
    flutter build web --release

# ============================================
# Stage 2: Serve with Nginx
# ============================================
FROM nginx:alpine

# Copy the built Flutter web files from the build stage
COPY --from=build-stage /app/build/web /usr/share/nginx/html

# Copy nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
