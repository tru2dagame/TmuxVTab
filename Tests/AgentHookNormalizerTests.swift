import Foundation
import Testing
@testable import TmuxVTab

struct AgentHookNormalizerTests {
  @Test func normalizesClaudePrompt() throws {
    let input = try #require("""
      {
        "session_id": "claude-session",
        "hook_event_name": "UserPromptSubmit",
        "cwd": "/repo",
        "permission_mode": "plan",
        "prompt": "Explain the failing test"
      }
      """.data(using: .utf8))

    let event = try #require(AgentHookNormalizer.normalize(
      agentHint: "auto",
      eventHint: "user-prompt-submit",
      input: input,
      environment: [
        "TMUX_PANE": "%7",
        "CLAUDE_PLUGIN_ROOT": "/plugin",
        "TMUXVTAB_HOOK_VERSION": HookVersion.current,
      ]
    ))

    #expect(event.source == .claude)
    #expect(event.kind == .userPrompt)
    #expect(event.paneID == "%7")
    #expect(event.prompt == "Explain the failing test")
    #expect(event.permissionMode == "plan")
    #expect(event.hookVersion == HookVersion.current)
  }

  @Test func detectsCodexAndNormalizesCompletion() throws {
    let input = try #require("""
      {
        "session_id": "codex-session",
        "turn_id": "turn-42",
        "hook_event_name": "Stop",
        "last_assistant_message": "Implemented and tested"
      }
      """.data(using: .utf8))

    let event = try #require(AgentHookNormalizer.normalize(
      agentHint: "auto",
      eventHint: "stop",
      input: input,
      environment: ["TMUX_PANE": "%9", "PLUGIN_ROOT": "/plugin"]
    ))

    #expect(event.source == .codex)
    #expect(event.kind == .completed)
    #expect(event.turnID == "turn-42")
    #expect(event.response == "Implemented and tested")
  }

  @Test func extractsApprovalDescriptionWithoutSerializingWholeToolInput() throws {
    let input = try #require("""
      {
        "session_id": "codex-session",
        "hook_event_name": "PermissionRequest",
        "tool_name": "Bash",
        "tool_input": {
          "command": "make release",
          "description": "Build the release artifact",
          "secret": "must-not-be-copied"
        }
      }
      """.data(using: .utf8))

    let event = try #require(AgentHookNormalizer.normalize(
      agentHint: "codex",
      eventHint: "permission-request",
      input: input,
      environment: ["TMUX_PANE": "%3"]
    ))

    #expect(event.kind == .approvalRequired)
    #expect(event.detail == "Build the release artifact")
    #expect(event.toolName == "Bash")
    #expect(event.detail?.contains("must-not-be-copied") == false)
  }

  @Test func mapsClaudeIdleAndInputNotificationsToNonWorkingStates() throws {
    let idle = try #require(AgentHookNormalizer.normalize(
      agentHint: "claude",
      eventHint: "notification",
      input: Data("""
        {
          "session_id": "claude-session",
          "hook_event_name": "Notification",
          "notification_type": "idle_prompt",
          "message": "Claude is waiting for input"
        }
        """.utf8),
      environment: ["TMUX_PANE": "%5"]
    ))
    #expect(idle.kind == .idle)
    #expect(idle.detail == "Claude is waiting for input")

    let needsInput = try #require(AgentHookNormalizer.normalize(
      agentHint: "claude",
      eventHint: "notification",
      input: Data("""
        {
          "session_id": "claude-session",
          "hook_event_name": "Notification",
          "notification_type": "agent_needs_input",
          "message": "A background agent needs input"
        }
        """.utf8),
      environment: ["TMUX_PANE": "%5"]
    ))
    #expect(needsInput.kind == .approvalRequired)
    #expect(needsInput.detail == "A background agent needs input")
  }

  @Test func requiresTmuxPaneAndBoundsPreviewText() throws {
    let longPrompt = String(repeating: "a", count: AgentHookNormalizer.maximumPromptLength + 20)
    let input = try JSONSerialization.data(withJSONObject: [
      "session_id": "session",
      "hook_event_name": "UserPromptSubmit",
      "prompt": longPrompt,
    ])

    #expect(AgentHookNormalizer.normalize(
      agentHint: "claude",
      eventHint: "user-prompt-submit",
      input: input,
      environment: [:]
    ) == nil)

    let event = try #require(AgentHookNormalizer.normalize(
      agentHint: "claude",
      eventHint: "user-prompt-submit",
      input: input,
      environment: ["TMUX_PANE": "%1"]
    ))
    #expect(event.prompt?.count == AgentHookNormalizer.maximumPromptLength + 1)
    #expect(event.prompt?.hasSuffix("…") == true)
  }
}
