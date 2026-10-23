namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

internal static class DumpHeaderVerifier
{
    internal readonly record struct Verification(
        string Status,
        string Detail,
        string Streams,
        bool HasException,
        bool HasModules);

    internal static Verification Verify(byte[] header, byte[] directory, long fileLength)
    {
        if (header is null || header.Length < 32 || fileLength < 32)
            return new("INVALID", "Dump 小于 Minidump 文件头，文件不完整。", "", false, false);
        if (BitConverter.ToUInt32(header, 0) != 0x504D444D)
            return new("INVALID", "不是 Windows Minidump（MDMP 签名不对）。", "", false, false);

        var version = BitConverter.ToUInt32(header, 4);
        var count = BitConverter.ToUInt32(header, 8);
        var stamp = BitConverter.ToUInt32(header, 20);
        var flags = BitConverter.ToUInt64(header, 24);
        if (count == 0 || count > 4096)
            return new("INVALID", "流目录数量异常，Dump 头不可信。", "", false, false);

        var expected = (int)count * 12;
        if (directory is null || directory.Length < expected)
            return new("PARTIAL", $"MDMP 签名正确，但流目录不完整（声明 {count} 个流）。", "", false, false);

        var names = new List<string>();
        var overflow = 0;
        var hasException = false;
        var hasModules = false;
        for (var i = 0; i < count; i++)
        {
            var offset = i * 12;
            var type = BitConverter.ToUInt32(directory, offset);
            var size = BitConverter.ToUInt32(directory, offset + 4);
            var rva = BitConverter.ToUInt32(directory, offset + 8);
            if (size > 0 && (rva < 32 || (long)rva + size > fileLength)) overflow++;
            if (type == 6) hasException = true;
            if (type == 4) hasModules = true;
            var name = StreamName(type);
            if (name.Length > 0 && names.Count < 12 && !names.Contains(name)) names.Add(name);
        }

        var time = "";
        if (stamp > 0)
        {
            try { time = DateTimeOffset.FromUnixTimeSeconds(stamp).ToLocalTime().ToString("yyyy-MM-dd HH:mm"); }
            catch { }
        }
        var notes = new List<string>();
        if ((version & 0xFFFF) != 0xA793) notes.Add("版本字不是 0xA793");
        if (overflow > 0) notes.Add($"{overflow} 个流超出文件末尾");
        if (!hasException) notes.Add("没有异常流");
        if ((flags & 0x2) != 0) notes.Add("含完整内存页，分析不会读取或上传这些页");

        var when = time.Length == 0 ? "" : $"，时间 {time}";
        var listed = names.Count == 0 ? "" : " 流：" + string.Join("、", names);
        if (notes.Count == 0)
            return new("VALID", $"Minidump 校验通过。{count} 个流{when}。{listed}", string.Join(",", names), hasException, hasModules);
        return new("PARTIAL", $"MDMP 签名在，校验不完整：{string.Join("；", notes)}。{count} 个流{when}。{listed}", string.Join(",", names), hasException, hasModules);
    }

    private static string StreamName(uint type) => type switch
    {
        3 => "ThreadList",
        4 => "ModuleList",
        5 => "MemoryList",
        6 => "Exception",
        7 => "SystemInfo",
        9 => "Memory64",
        15 => "Comment",
        21 => "MiscInfo",
        _ => ""
    };
}
