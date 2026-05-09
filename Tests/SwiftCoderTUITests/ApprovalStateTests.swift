import XCTest
@testable import SwiftCoderTUI

final class ApprovalStateTests: XCTestCase {
    func testMakeDoesNotDuplicateToolNameWhenDisplayAlreadyIncludesTool() {
        let state = ApprovalState.make(tool: "bash", args: "bash git status")
        XCTAssertEqual(state.message, "Do you want to proceed with 'bash git status'?")
        XCTAssertEqual(state.options[1], "Yes, allow 'bash git status' always in this session")
    }

    func testMakeCombinesToolAndArgsWhenArgsOnlyContainArguments() {
        let state = ApprovalState.make(tool: "bash", args: "git status")
        XCTAssertEqual(state.message, "Do you want to proceed with 'bash git status'?")
        XCTAssertEqual(state.options[1], "Yes, allow 'bash git status' always in this session")
    }
}
