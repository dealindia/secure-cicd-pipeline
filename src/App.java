import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

public class App {
    public static void main(String[] args) throws IOException {
        int port = Integer.parseInt(System.getenv().getOrDefault("PORT", "8080"));
        HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", port), 0);

        server.createContext("/api/health", ex -> send(ex, 200, "{\"status\":\"UP\"}"));
        server.createContext("/api/hello", ex -> {
            String query = ex.getRequestURI().getQuery();
            String name = (query != null && query.startsWith("name=")) ? query.substring(5) : "World";
            // Allow only safe characters so user input can't break the JSON output
            name = name.replaceAll("[^A-Za-z0-9 _-]", "");
            if (name.isEmpty() || name.length() > 50) name = "World";
            send(ex, 200, "{\"message\":\"Hello, " + name + "!\"}");
        });

        // "/" answers 200 (default health and DAST path); any other unknown path
        // gets a JSON 404. Both carry the security headers.
        server.createContext("/", ex -> {
            if ("/".equals(ex.getRequestURI().getPath())) {
                send(ex, 200, "{\"service\":\"sample-api\",\"endpoints\":[\"/api/health\",\"/api/hello?name=you\"]}");
            } else {
                send(ex, 404, "{\"error\":\"Not Found\"}");
            }
        });

        server.start();
        System.out.println("API listening on port " + port);
    }

    private static void send(HttpExchange ex, int status, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        var headers = ex.getResponseHeaders();
        headers.set("Content-Type", "application/json; charset=utf-8");
        // Security headers (checked by the DAST scan)
        headers.set("X-Content-Type-Options", "nosniff");
        headers.set("X-Frame-Options", "DENY");
        headers.set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'");
        headers.set("Cache-Control", "no-store");
        headers.set("Referrer-Policy", "no-referrer");
        headers.set("Permissions-Policy", "geolocation=(), camera=(), microphone=()");
        headers.set("Cross-Origin-Resource-Policy", "same-origin");
        ex.sendResponseHeaders(status, bytes.length);
        try (OutputStream os = ex.getResponseBody()) {
            os.write(bytes);
        }
    }
}
