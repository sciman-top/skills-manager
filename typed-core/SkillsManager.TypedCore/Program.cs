using System.Text;
using System.Text.Json;

namespace SkillsManager.TypedCore;

internal static class Program
{
    private const int ValidationFailedExitCode = 2;
    private const int InvalidRequestExitCode = 64;
    private const int InternalErrorExitCode = 70;

    public static async Task<int> Main()
    {
        Console.OutputEncoding = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);

        try
        {
            using JsonDocument request = await JsonDocument.ParseAsync(
                Console.OpenStandardInput(),
                new JsonDocumentOptions { AllowTrailingCommas = false, CommentHandling = JsonCommentHandling.Disallow });

            if (!TryReadRequest(request.RootElement, out string operation, out JsonElement payload, out Finding? requestFinding))
            {
                WriteResult("invalid_request", false, [requestFinding!]);
                return InvalidRequestExitCode;
            }

            ValidationResult result = operation switch
            {
                "validate_plan" => OperationContractValidator.ValidatePlan(payload),
                "validate_receipt" => OperationContractValidator.ValidateReceipt(payload),
                _ => ValidationResult.InvalidRequest("operation_unsupported", "$.operation", "Operation is not supported.")
            };

            if (result.IsRequestError)
            {
                WriteResult(operation, false, result.Findings);
                return InvalidRequestExitCode;
            }

            WriteResult(operation, result.Pass, result.Findings);
            return result.Pass ? 0 : ValidationFailedExitCode;
        }
        catch (JsonException)
        {
            WriteResult("invalid_request", false, [new Finding("request_json_invalid", "error", "$", "Request must be valid JSON.")]);
            return InvalidRequestExitCode;
        }
        catch (Exception)
        {
            WriteResult("internal_error", false, [new Finding("internal_error", "error", "$", "Typed-core shadow validation failed unexpectedly.")]);
            return InternalErrorExitCode;
        }
    }

    private static bool TryReadRequest(JsonElement root, out string operation, out JsonElement payload, out Finding? finding)
    {
        operation = "invalid_request";
        payload = default;
        finding = null;

        if (root.ValueKind != JsonValueKind.Object)
        {
            finding = new Finding("request_type_invalid", "error", "$", "Request must be a JSON object.");
            return false;
        }

        if (!OperationContractValidator.TryGetProperty(root, "protocol_version", out JsonElement version) ||
            version.ValueKind != JsonValueKind.Number || !version.TryGetInt32(out int protocolVersion) || protocolVersion != 1)
        {
            finding = new Finding("protocol_version_invalid", "error", "$.protocol_version", "Only protocol version 1 is supported.");
            return false;
        }

        if (!OperationContractValidator.TryGetProperty(root, "operation", out JsonElement operationElement) || operationElement.ValueKind != JsonValueKind.String)
        {
            finding = new Finding("operation_missing", "error", "$.operation", "Operation is required.");
            return false;
        }

        operation = operationElement.GetString() ?? string.Empty;
        if (!OperationContractValidator.TryGetProperty(root, "payload", out payload))
        {
            finding = new Finding("payload_missing", "error", "$.payload", "Payload is required.");
            return false;
        }

        return true;
    }

    private static void WriteResult(string operation, bool pass, IReadOnlyList<Finding> findings)
    {
        var response = new
        {
            protocol_version = 1,
            operation,
            pass,
            findings
        };
        Console.WriteLine(JsonSerializer.Serialize(response, JsonDefaults.Options));
    }
}
