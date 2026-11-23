# ---- Build stage ----
FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /build
COPY src/ src/
RUN mkdir out && javac -d out src/*.java \
 && printf 'Main-Class: App\n' > manifest.txt \
 && jar cfm app.jar manifest.txt -C out .

# ---- Runtime stage ----
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app
COPY --from=build /build/app.jar app.jar
USER app

ENV PORT=8080
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:8080/api/health || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
