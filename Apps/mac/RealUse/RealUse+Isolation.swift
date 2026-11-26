import AppKit

// 실사용 시뮬레이션 — 자동화 실행의 격리 (AutomationRun.swift): 이 실행이 사용자의 것을 건드리지 않는가. 검사는 셀프테스트와 같이 쓴다
// (IsolationProbe, SelfTest+Isolation.swift). 시나리오 목록의 맨 끝에 둔다 — 전체 실행에서는 그 실행 동안 바뀐 것이 없는지도 본다
extension RealUse {
    @MainActor static let isolationScenarios: [Scenario] = [
        Scenario(name: "automation-isolated") { ctx in
            ctx.at("window frames")
            for r in IsolationProbe.windowFrames(ctx.window) { if r.ok { ctx.note(r.what) } else { ctx.issue("isolation", r.what, snap: false) } }
            ctx.at("stays in the background")
            for r in await IsolationProbe.background(model: ctx.model) { if r.ok { ctx.note(r.what) } else { ctx.issue("isolation", r.what, snap: false) } }
            ctx.at("global shortcut")
            for r in await IsolationProbe.globalShortcut(model: ctx.model) { if r.ok { ctx.note(r.what) } else { ctx.issue("isolation", r.what, snap: false) } }
            await ctx.settle(200)
            ctx.checkAll("after the isolation checks")
        },
    ]
}
