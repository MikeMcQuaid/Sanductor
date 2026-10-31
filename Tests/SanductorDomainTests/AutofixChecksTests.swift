import SanductorDomain
import Testing

struct AutofixChecksTests {
    @Test
    func `completed failures are available before other required results`() {
        let failed = AutofixCheck(name: "test", status: "COMPLETED", conclusion: "FAILURE", runID: "1", link: "test")
        let pending = AutofixCheck(name: "build", status: "IN_PROGRESS", conclusion: "", runID: "2", link: "build")
        #expect(AutofixChecks(required: ["test", "build"], results: [failed]).failures == [failed])
        #expect(AutofixChecks(required: ["test", "build"], results: [failed, pending]).failures == [failed])
        let passed = AutofixCheck(name: "build", status: "COMPLETED", conclusion: "SUCCESS", runID: "2", link: "build")
        #expect(AutofixChecks(required: ["test", "build"], results: [failed, passed]).failures == [failed])
    }

    @Test
    func `unfinished optional jobs do not hide completed failures`() {
        let optional = AutofixCheck(
            name: "optional",
            status: "IN_PROGRESS",
            conclusion: "FAILURE",
            runID: "2",
            link: "optional",
        )
        let failed = AutofixCheck(name: "test", status: "COMPLETED", conclusion: "FAILURE", runID: "1", link: "test")
        #expect(AutofixChecks(required: ["test"], results: [failed, optional]).isComplete == false)
        #expect(AutofixChecks(required: [], results: [failed]).failures == [failed])
        #expect(AutofixChecks(required: ["optional"], results: [failed, optional]).failures == [failed])
    }

    @Test
    func `unknown completion never counts as finished`() {
        let check = AutofixCheck(name: "test", status: "", conclusion: "FAILURE", runID: "1", link: "test")
        #expect(AutofixChecks(required: ["test"], results: [check]).failures.isEmpty)
    }
}
