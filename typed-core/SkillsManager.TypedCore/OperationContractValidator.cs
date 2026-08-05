using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace SkillsManager.TypedCore;

internal sealed record Finding(
    [property: JsonPropertyName("code")] string Code,
    [property: JsonPropertyName("severity")] string Severity,
    [property: JsonPropertyName("path")] string Path,
    [property: JsonPropertyName("message")] string Message);

internal sealed record ValidationResult(bool Pass, IReadOnlyList<Finding> Findings, bool IsRequestError = false)
{
    public static ValidationResult InvalidRequest(string code, string path, string message) =>
        new(false, [new Finding(code, "error", path, message)], true);
}

internal static class JsonDefaults
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = null,
        WriteIndented = false
    };
}

internal static partial class OperationContractValidator
{
    private static readonly HashSet<string> PlanDomains = new(StringComparer.Ordinal)
    {
        "mcp", "skill_projection", "rules", "plugin"
    };

    private static readonly HashSet<string> PlanModes = new(StringComparer.Ordinal)
    {
        "dry_run", "apply"
    };

    private static readonly HashSet<string> ActionTypes = new(StringComparer.Ordinal)
    {
        "create", "update", "delete", "native_command"
    };

    private static readonly HashSet<string> Risks = new(StringComparer.Ordinal)
    {
        "low", "medium", "high"
    };

    private static readonly HashSet<string> ReceiptStatuses = new(StringComparer.Ordinal)
    {
        "dry_run", "applied", "partial", "failed", "rolled_back"
    };

    private static readonly string[] VerificationLevels =
    [
        "static_validated", "repo_gates_passed", "host_loaded", "live_accepted"
    ];

    private static readonly HashSet<string> VerificationStates = new(StringComparer.Ordinal)
    {
        "pass", "fail", "not_run", "not_applicable"
    };

    public static ValidationResult ValidatePlan(JsonElement plan)
    {
        List<Finding> findings = [];
        if (plan.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
        {
            return Result([FindingOf("plan_missing", "$", "Plan is required.")]);
        }

        if (ReadInt32(plan, "schema_version") != 1)
        {
            findings.Add(FindingOf("schema_version_invalid", "$.schema_version", "Only schema version 1 is supported."));
        }

        foreach (string field in new[] { "operation_id", "domain", "mode", "created_at" })
        {
            if (string.IsNullOrWhiteSpace(ReadText(plan, field)))
            {
                findings.Add(FindingOf("required_field_missing", $"$.{field}", "Required field is missing."));
            }
        }

        if (!IsRfc3339(GetPropertyOrUndefined(plan, "created_at")))
        {
            findings.Add(FindingOf("created_at_invalid", "$.created_at", "Created time must be RFC3339."));
        }

        if (!PlanDomains.Contains(ReadText(plan, "domain")))
        {
            findings.Add(FindingOf("domain_invalid", "$.domain", "Domain is not supported."));
        }

        if (!PlanModes.Contains(ReadText(plan, "mode")))
        {
            findings.Add(FindingOf("mode_invalid", "$.mode", "Mode is not supported."));
        }

        JsonElement targets = GetPropertyOrUndefined(plan, "targets");
        JsonElement actions = GetPropertyOrUndefined(plan, "actions");
        if (targets.ValueKind != JsonValueKind.Array)
        {
            findings.Add(FindingOf("targets_type_invalid", "$.targets", "Targets must be an array."));
        }
        if (actions.ValueKind != JsonValueKind.Array)
        {
            findings.Add(FindingOf("actions_type_invalid", "$.actions", "Actions must be an array."));
        }

        foreach (string field in new[] { "preconditions", "verification", "rollback" })
        {
            if (GetPropertyOrUndefined(plan, field).ValueKind != JsonValueKind.Array)
            {
                findings.Add(FindingOf("array_type_invalid", $"$.{field}", "Plan field must be an array."));
            }
        }

        HashSet<string> targetRefs = new(StringComparer.OrdinalIgnoreCase);
        if (targets.ValueKind == JsonValueKind.Array)
        {
            int index = 0;
            foreach (JsonElement target in targets.EnumerateArray())
            {
                string targetRef = ReadText(target, "target_ref");
                if (string.IsNullOrWhiteSpace(targetRef) || !targetRefs.Add(targetRef))
                {
                    findings.Add(FindingOf("target_ref_invalid", $"$.targets[{index}].target_ref", "Target reference is missing or duplicated."));
                }

                foreach (string field in new[] { "path", "desired_hash", "owner" })
                {
                    if (string.IsNullOrWhiteSpace(ReadText(target, field)))
                    {
                        findings.Add(FindingOf("target_field_missing", $"$.targets[{index}].{field}", "Target field is required."));
                    }
                }

                foreach (string hashField in new[] { "before_hash", "desired_hash" })
                {
                    JsonElement hashValue = GetPropertyOrUndefined(target, hashField);
                    if (hashValue.ValueKind is not JsonValueKind.Null and not JsonValueKind.Undefined && !Sha256Regex().IsMatch(ElementText(hashValue)))
                    {
                        findings.Add(FindingOf("hash_invalid", $"$.targets[{index}].{hashField}", "Hash must be SHA-256 or null."));
                    }
                }
                index++;
            }
        }

        HashSet<string> actionIds = new(StringComparer.OrdinalIgnoreCase);
        if (actions.ValueKind == JsonValueKind.Array)
        {
            int index = 0;
            foreach (JsonElement action in actions.EnumerateArray())
            {
                string actionId = ReadText(action, "action_id");
                if (string.IsNullOrWhiteSpace(actionId) || !actionIds.Add(actionId))
                {
                    findings.Add(FindingOf("action_id_invalid", $"$.actions[{index}].action_id", "Action ID is missing or duplicated."));
                }
                else if (!ActionIdRegex().IsMatch(actionId))
                {
                    findings.Add(FindingOf("action_id_format_invalid", $"$.actions[{index}].action_id", "Action ID format is invalid."));
                }

                if (!ActionTypes.Contains(ReadText(action, "type")))
                {
                    findings.Add(FindingOf("action_type_invalid", $"$.actions[{index}].type", "Action type is not supported."));
                }
                if (!Risks.Contains(ReadText(action, "risk")))
                {
                    findings.Add(FindingOf("risk_invalid", $"$.actions[{index}].risk", "Risk is not supported."));
                }
                if (!targetRefs.Contains(ReadText(action, "target_ref")))
                {
                    findings.Add(FindingOf("action_target_unknown", $"$.actions[{index}].target_ref", "Action target is not declared."));
                }
                index++;
            }
        }

        if (SensitiveValueRegex().IsMatch(plan.GetRawText()))
        {
            findings.Add(FindingOf("sensitive_value_present", "$", "Plan contains a sensitive value."));
        }

        return Result(findings);
    }

    public static ValidationResult ValidateReceipt(JsonElement receipt)
    {
        List<Finding> findings = [];
        if (receipt.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
        {
            return Result([FindingOf("receipt_missing", "$", "Receipt is required.")]);
        }

        if (ReadInt32(receipt, "schema_version") != 1)
        {
            findings.Add(FindingOf("schema_version_invalid", "$.schema_version", "Only schema version 1 is supported."));
        }

        foreach (string field in new[] { "operation_id", "status", "started_at", "completed_at" })
        {
            if (string.IsNullOrWhiteSpace(ReadText(receipt, field)))
            {
                findings.Add(FindingOf("required_field_missing", $"$.{field}", "Required field is missing."));
            }
        }

        foreach (string field in new[] { "started_at", "completed_at" })
        {
            if (!IsRfc3339(GetPropertyOrUndefined(receipt, field)))
            {
                findings.Add(FindingOf("timestamp_invalid", $"$.{field}", "Receipt time must be RFC3339."));
            }
        }

        if (!ReceiptStatuses.Contains(ReadText(receipt, "status")))
        {
            findings.Add(FindingOf("status_invalid", "$.status", "Receipt status is not supported."));
        }

        foreach (string field in new[] { "actions", "backups", "rollback" })
        {
            if (GetPropertyOrUndefined(receipt, field).ValueKind != JsonValueKind.Array)
            {
                findings.Add(FindingOf("array_type_invalid", $"$.{field}", "Receipt field must be an array."));
            }
        }

        JsonElement verification = GetPropertyOrUndefined(receipt, "verification");
        foreach (string level in VerificationLevels)
        {
            if (!VerificationStates.Contains(ReadText(verification, level)))
            {
                findings.Add(FindingOf("verification_state_invalid", $"$.verification.{level}", "Verification state is not supported."));
            }
        }

        if (SensitiveValueRegex().IsMatch(receipt.GetRawText()))
        {
            findings.Add(FindingOf("sensitive_value_present", "$", "Receipt contains a sensitive value."));
        }

        return Result(findings);
    }

    internal static bool TryGetProperty(JsonElement element, string name, out JsonElement value)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            foreach (JsonProperty property in element.EnumerateObject())
            {
                if (string.Equals(property.Name, name, StringComparison.OrdinalIgnoreCase))
                {
                    value = property.Value;
                    return true;
                }
            }
        }
        value = default;
        return false;
    }

    private static JsonElement GetPropertyOrUndefined(JsonElement element, string name) =>
        TryGetProperty(element, name, out JsonElement value) ? value : default;

    private static int? ReadInt32(JsonElement element, string name)
    {
        JsonElement value = GetPropertyOrUndefined(element, name);
        return value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out int parsed) ? parsed : null;
    }

    private static string ReadText(JsonElement element, string name) => ElementText(GetPropertyOrUndefined(element, name));

    private static string ElementText(JsonElement element) => element.ValueKind switch
    {
        JsonValueKind.String => element.GetString() ?? string.Empty,
        JsonValueKind.Null or JsonValueKind.Undefined => string.Empty,
        _ => element.GetRawText()
    };

    private static bool IsRfc3339(JsonElement value)
    {
        string text = ElementText(value);
        return Rfc3339Regex().IsMatch(text) && DateTimeOffset.TryParse(
            text,
            CultureInfo.InvariantCulture,
            DateTimeStyles.RoundtripKind,
            out _);
    }

    private static Finding FindingOf(string code, string path, string message) => new(code, "error", path, message);

    private static ValidationResult Result(IReadOnlyList<Finding> findings) =>
        new(!findings.Any(finding => finding.Severity == "error"), findings);

    [GeneratedRegex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,7})?(?:Z|[+-]\\d{2}:\\d{2})$", RegexOptions.CultureInvariant)]
    private static partial Regex Rfc3339Regex();

    [GeneratedRegex("^[a-fA-F0-9]{64}$", RegexOptions.CultureInvariant)]
    private static partial Regex Sha256Regex();

    [GeneratedRegex("^act-[a-f0-9]{16}$", RegexOptions.CultureInvariant)]
    private static partial Regex ActionIdRegex();

    [GeneratedRegex("""(Bearer\s+(?!<redacted>)[A-Za-z0-9._-]+|postgres(?:ql)?://|(?:Password|Pwd)\s*[=:]\s*(?!<redacted>)[^;\s\"}]+|(?:[A-Z0-9_]*(?:API_?KEY|TOKEN|SECRET|PASSWORD|PASSWD|PWD))\s*=\s*(?!<redacted>)[^\s\"}]+|gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]{8,}|[?&](?:access_token|api_key|apikey|token|secret|password|key)=(?!<redacted>)[^&#\s\"}]+|\"(?:token|api_key|apikey|password|passwd|pwd|secret|authorization|connection_string|oauth)[^\"]*\"\s*:\s*\"(?!<redacted>))""", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex SensitiveValueRegex();
}
