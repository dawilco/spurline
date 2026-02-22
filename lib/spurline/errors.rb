# frozen_string_literal: true

# Eagerly loaded by lib/spurline.rb and ignored by Zeitwerk.
# This is the one file that breaks the autoloading convention, because
# error classes must be available before any framework code runs and
# they define multiple constants directly under Spurline.

module Spurline
  # Base error for all Spurline errors. Rescue this to catch any framework error.
  class AgentError < StandardError; end

  # Raised when tainted content (trust: :external or :untrusted) is converted
  # to a string via #to_s. Use Content#render instead, which applies data fencing.
  class TaintedContentError < AgentError; end

  # Raised when the injection scanner detects a prompt injection pattern
  # in content flowing through the context pipeline.
  class InjectionAttemptError < AgentError; end

  # Raised when the PII filter in :block mode detects personally identifiable
  # information in content. Switch to :redact mode to allow content through
  # with PII replaced, or :off to disable filtering.
  class PIIDetectedError < AgentError; end

  # Raised when a tool execution is denied by the permission system.
  # Check config/permissions.yml for the tool's permission requirements.
  class PermissionDeniedError < AgentError; end

  # Raised when code attempts to modify a compiled persona at runtime.
  # Personas are frozen on class load — define a new persona instead.
  class PersonaFrozenError < AgentError; end

  # Raised when an agent attempts an invalid lifecycle state transition.
  # Check Spurline::Lifecycle::States for valid transitions.
  class InvalidStateError < AgentError; end

  # Raised when a tool call references a tool name not in the registry.
  # Ensure the tool's spur gem is installed and required.
  class ToolNotFoundError < AgentError; end

  # Raised when the per-turn tool call limit (guardrails.max_tool_calls) is exceeded.
  # Increase the limit in the agent's guardrails block or restructure the task.
  class MaxToolCallsError < AgentError; end

  # Raised when a tool attempts to invoke another tool. Tools are leaf nodes (ADR-003).
  # Use a Spurline::Skill if you need to compose multiple tools.
  class NestedToolCallError < AgentError; end

  # Raised when an adapter symbol cannot be resolved in the adapter registry.
  # Ensure the adapter is registered before referencing it in use_model.
  class AdapterNotFoundError < AgentError; end

  # Raised when the sqlite3 gem is unavailable but the SQLite session store is used.
  # Add gem "sqlite3" to the application bundle when configuring :sqlite session storage.
  class SQLiteUnavailableError < AgentError; end

  # Raised when the pg gem is unavailable but the Postgres session store is used.
  # Add gem "pg" to the application bundle when configuring :postgres session storage.
  class PostgresUnavailableError < AgentError; end

  # Raised when persisted session payloads cannot be decoded into Session/Turn objects.
  # This indicates corrupted or incompatible serialized session data.
  class SessionDeserializationError < AgentError; end

  # Raised when Spurline.configure or a DSL method receives invalid configuration.
  # This always fires at class load time, never at runtime.
  class ConfigurationError < AgentError; end

  # Raised when encrypted credentials exist but no master key can be resolved.
  class CredentialsMissingKeyError < AgentError; end

  # Raised when encrypted credentials cannot be decrypted (bad key or tampered file).
  class CredentialsDecryptionError < AgentError; end

  # Raised when a required tool secret cannot be resolved from any configured source.
  class SecretNotFoundError < AgentError; end

  # Raised when an embedding provider or model fails to produce a valid vector.
  class EmbedderError < AgentError; end

  # Raised when long-term memory persistence or retrieval fails.
  class LongTermMemoryError < AgentError; end

  # Raised when Cartographer cannot access the target repository path.
  class CartographerAccessError < AgentError; end

  # Raised when an individual analyzer fails to produce valid output.
  class AnalyzerError < AgentError; end
end
