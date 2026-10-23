using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;
using Xunit;

namespace WGR.Tests;

public sealed class DumpHeaderTests
{
    [Fact]
    public void Valid_header_with_exception_stream_passes()
    {
        var header = new byte[32];
        BitConverter.TryWriteBytes(header.AsSpan(0), 0x504D444D);
        BitConverter.TryWriteBytes(header.AsSpan(4), 0xA793);
        BitConverter.TryWriteBytes(header.AsSpan(8), 1u);
        BitConverter.TryWriteBytes(header.AsSpan(12), 32u);
        BitConverter.TryWriteBytes(header.AsSpan(20), 1_700_000_000u);
        var directory = new byte[12];
        BitConverter.TryWriteBytes(directory.AsSpan(0), 6u);
        BitConverter.TryWriteBytes(directory.AsSpan(4), 152u);
        BitConverter.TryWriteBytes(directory.AsSpan(8), 44u);

        var result = DumpHeaderVerifier.Verify(header, directory, 44 + 152);

        Assert.Equal("VALID", result.Status);
        Assert.Contains("Exception", result.Streams);
        Assert.True(result.HasException);
    }

    [Fact]
    public void Bad_signature_is_invalid()
    {
        var result = DumpHeaderVerifier.Verify(new byte[32], Array.Empty<byte>(), 32);
        Assert.Equal("INVALID", result.Status);
    }

    [Fact]
    public void Truncated_directory_is_partial()
    {
        var header = new byte[32];
        BitConverter.TryWriteBytes(header.AsSpan(0), 0x504D444D);
        BitConverter.TryWriteBytes(header.AsSpan(4), 0xA793);
        BitConverter.TryWriteBytes(header.AsSpan(8), 2u);
        var result = DumpHeaderVerifier.Verify(header, new byte[12], 64);
        Assert.Equal("PARTIAL", result.Status);
    }

    [Fact]
    public void DeepSeek_prompt_sends_summary_not_path()
    {
        var prompt = DeepSeekDumpClient.BuildUserPrompt(new DumpAnalysisResult
        {
            FileName = "game.dmp",
            FilePath = @"C:\Users\secret\game.dmp",
            ExceptionCode = "0xC0000005",
            ExceptionName = "Access Violation",
            FaultingModule = "game.exe",
            VerifyStatus = "VALID",
            VerifyDetail = "Minidump 校验通过",
            CoreReason = "访问冲突"
        });

        Assert.Contains("0xC0000005", prompt);
        Assert.Contains("game.dmp", prompt);
        Assert.DoesNotContain("secret", prompt);
        Assert.Contains("api.deepseek.com", DeepSeekDumpClient.Endpoint);
    }
}
