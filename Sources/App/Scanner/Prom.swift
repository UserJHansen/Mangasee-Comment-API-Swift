import Metrics
import Prometheus
import Vapor

enum ScannerStatistics {
    static var comments: PromCounter<Int>?
    static var replies: PromCounter<Int>?
    static var users: PromCounter<Int>?

    static var discussions: PromCounter<Int>?
    static var manga: PromCounter<Int>?

    static var timing: PromHistogram<Double>?

    static var isMetricEnabled: Bool {
        comments != nil
    }
}

struct LoggingMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)

        let code = response.status.code
        let method = request.method.string
        let path = request.url.path

        total.inc(1, [("code", String(code)), ("method", method), ("url", path)])
        size.observe(request.body.data?.readableBytes ?? 0)

        return response
    }

    let total: PromCounter<Int>
    let size: PromSummary<Int>
    init(counter total: PromCounter<Int>, size: PromSummary<Int>) {
        self.total = total
        self.size = size
    }
}

func startProm(using cont: CommandContext) throws {
    let prom = PrometheusClient()
    MetricsSystem.bootstrap(PrometheusMetricsFactory(client: prom))

    ScannerStatistics.comments = prom.createCounter(forType: Int.self, named: "mangasee_comments_total", helpText: "Total number of comments.")
    ScannerStatistics.replies = prom.createCounter(forType: Int.self, named: "mangasee_replies_total", helpText: "Total number of replies.")
    ScannerStatistics.users = prom.createCounter(forType: Int.self, named: "mangasee_users_total", helpText: "Total number of users.")
    ScannerStatistics.discussions = prom.createCounter(forType: Int.self, named: "mangasee_discussions_total", helpText: "Total number of discussions.")
    ScannerStatistics.manga = prom.createCounter(forType: Int.self, named: "mangasee_manga_total", helpText: "Total number of manga.")
    ScannerStatistics.timing = prom.createHistogram(forType: Double.self, named: "mangasee_scan_duration_seconds", helpText: "The time it takes to scan a page.")

    let reqCounter = prom.createCounter(forType: Int.self, named: "mangasee_requests_total", helpText: "Total number of requests, partitioned by status code and HTTP method.")
    let reqSize = prom.createSummary(forType: Int.self, named: "mangasee_request_size_bytes", helpText: "The HTTP request sizes in bytes.")

    cont.application.middleware.use(LoggingMiddleware(counter: reqCounter, size: reqSize))
    cont.application.get("metrics") { _ async throws -> String in
        try await MetricsSystem.prometheus().collect()
    }
}
