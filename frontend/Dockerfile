# ============================================
# Stage 1: Build Flutter Web
# ============================================
FROM ghcr.io/cirruslabs/flutter:stable AS build-stage

WORKDIR /app
COPY . .
RUN flutter build web --release

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
