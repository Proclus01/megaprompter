import XCTest
@testable import MegaDocCore

final class UMLHTTPMethodDetectionTests: XCTestCase {

  func test_go_router_methods_are_detected() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("uml_go_methods_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    let goFile = tmp.appendingPathComponent("routes.go")
    try """
    package main

    func Routes(r Router) {
      r.POST("/submit", handler)
      r.GET("/health", handler)
    }
    """.write(to: goFile, atomically: true, encoding: .utf8)

    let builder = UMLBuilder(root: tmp, imports: [], files: [goFile], maxAnalyzeBytes: 50_000, granularity: .file)
    let diagram = builder.build(includeIO: false, includeEndpoints: true, maxNodes: 50)

    let endpointLabels = diagram.nodes.filter { $0.kind == .endpoint }.map { $0.label }
    XCTAssertTrue(endpointLabels.contains("(POST /submit)"), "Expected POST /submit endpoint node")
    XCTAssertTrue(endpointLabels.contains("(GET /health)"), "Expected GET /health endpoint node")
  }

  func test_spring_postmapping_is_detected_as_post() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("uml_java_methods_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    let javaFile = tmp.appendingPathComponent("Controller.java")
    try """
    import org.springframework.web.bind.annotation.*;

    public class Controller {
      @PostMapping("/v1/items")
      public String create() { return "ok"; }
    }
    """.write(to: javaFile, atomically: true, encoding: .utf8)

    let builder = UMLBuilder(root: tmp, imports: [], files: [javaFile], maxAnalyzeBytes: 50_000, granularity: .file)
    let diagram = builder.build(includeIO: false, includeEndpoints: true, maxNodes: 50)

    let endpointLabels = diagram.nodes.filter { $0.kind == .endpoint }.map { $0.label }
    XCTAssertTrue(endpointLabels.contains("(POST /v1/items)"), "Expected POST /v1/items endpoint node")
  }
}
