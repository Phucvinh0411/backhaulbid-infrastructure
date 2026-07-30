# ============================================
# Dockerfile for api-gateway (Standalone)
# ============================================

# Stage 1: Build with Maven
FROM maven:3.9-eclipse-temurin-21-alpine AS builder
WORKDIR /app

# Cache Maven dependencies
COPY pom.xml ./
RUN mvn dependency:go-offline -B --no-transfer-progress

# Copy source code and build
COPY src ./src
RUN mvn clean package -DskipTests -B --no-transfer-progress

# Stage 2: Runtime
FROM eclipse-temurin:21-jre-alpine AS runner
WORKDIR /app

RUN addgroup --system --gid 1001 spring
RUN adduser --system --uid 1001 spring

# Copy jar from builder
COPY --from=builder --chown=spring:spring /app/target/*.jar app.jar

USER spring

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
