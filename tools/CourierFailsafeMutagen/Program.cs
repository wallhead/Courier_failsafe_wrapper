using Mutagen.Bethesda;
using Mutagen.Bethesda.Plugins;
using Mutagen.Bethesda.Plugins.Records;
using Mutagen.Bethesda.Skyrim;

const string GameRoot = @"D:\TESV_EX";
const string Mo2Root = @"D:\TESV_EX\MO2";
const string SourceScriptsMod = @"D:\TESV_EX\MO2\mods\SKSE Scripts";
const string OutputModName = "Courier Failsafe Wrapper";
const string PluginName = "CourierFailsafe.esp";
const string QuestEditorId = "WICourierFailsafeQuest";
const string QuestScriptName = "WICourierFailsafeScript";
const string ForceDeliveryMessagePlaceholder = "..........................................................................................";
const string ForceDeliveryMessageRussian = "Курьер устал бегать за вами и прислал письма почтой. Не забудьте прочитать их в инвентаре!";
const uint QuestLocalFormId = 0x000800;

var outputModPath = Path.Combine(Mo2Root, "mods", OutputModName);
var outputPluginPath = Path.Combine(outputModPath, PluginName);
var outputSeqPath = Path.Combine(outputModPath, "Seq", "CourierFailsafe.seq");

Directory.CreateDirectory(outputModPath);
Directory.CreateDirectory(Path.Combine(outputModPath, "Scripts"));
Directory.CreateDirectory(Path.Combine(outputModPath, "Source", "Scripts"));
Directory.CreateDirectory(Path.Combine(outputModPath, "Seq"));

Console.WriteLine($"Output mod: {outputModPath}");

var skyrimMasterPath = Path.Combine(GameRoot, "Data", "Skyrim.esm");
if (!File.Exists(skyrimMasterPath))
{
    throw new FileNotFoundException("Could not find Skyrim.esm", skyrimMasterPath);
}

using var skyrim = SkyrimMod.CreateFromBinaryOverlay(skyrimMasterPath, SkyrimRelease.SkyrimSE);

var wiCourierKey = FindQuest(skyrim, "WICourier");
var courierContainerKey = FindPlacedObject(skyrim, "WICourierContainerRef");
var itemCountKey = FindGlobal(skyrim, "WICourierItemCount");
var playerRefKey = FormKey.Factory("000014:Skyrim.esm");

Console.WriteLine($"WICourier:          {wiCourierKey}");
Console.WriteLine($"CourierContainer:   {courierContainerKey}");
Console.WriteLine($"WICourierItemCount: {itemCountKey}");
Console.WriteLine($"PlayerRef:          {playerRefKey}");

var patchModKey = new ModKey(Path.GetFileNameWithoutExtension(PluginName), ModType.Plugin);
var patch = new SkyrimMod(patchModKey, SkyrimRelease.SkyrimSE);
((IMod)patch).MasterReferences.Add(new MasterReference
{
    Master = new ModKey("Skyrim", ModType.Master)
});

var questFormKey = FormKey.Factory($"{QuestLocalFormId:X6}:{PluginName}");
var quest = patch.Quests.AddNew(questFormKey);
quest.EditorID = QuestEditorId;
quest.Name = "WICourier Failsafe";
quest.Flags = Quest.Flag.StartGameEnabled;
quest.Priority = 0;
quest.Type = Quest.TypeEnum.Misc;
quest.QuestFormVersion = 65;
quest.NextAliasID = 0;
quest.VirtualMachineAdapter = new QuestAdapter();
quest.VirtualMachineAdapter.Scripts.Add(new ScriptEntry
{
    Name = QuestScriptName,
    Flags = ScriptEntry.Flag.Local,
    Properties =
    {
        ObjectProperty("WICourierQuest", wiCourierKey),
        ObjectProperty("CourierSystem", wiCourierKey),
        ObjectProperty("CourierContainer", courierContainerKey),
        ObjectProperty("PlayerRef", playerRefKey),
        ObjectProperty("WICourierItemCount", itemCountKey),
        BoolProperty("LogOnlyMode", false),
        BoolProperty("RequireSafeWorldForForceDelivery", true),
        BoolProperty("LogEnabled", true),
        BoolProperty("LogEveryCheck", false),
        StringProperty("LogName", "WICourierFailsafe"),
        StringProperty("ForceDeliveryMessage", ForceDeliveryMessagePlaceholder)
    }
});

patch.WriteToBinary(outputPluginPath);
ReplaceAsciiStringWithCp1251(outputPluginPath, ForceDeliveryMessagePlaceholder, ForceDeliveryMessageRussian);
SetEslFlag(outputPluginPath);
WriteSeq(outputSeqPath, QuestLocalFormId);
CopyScripts(SourceScriptsMod, outputModPath);
DeleteStaleAliasHelperScripts(outputModPath);

Console.WriteLine($"Plugin written: {outputPluginPath}");
Console.WriteLine($"SEQ written:    {outputSeqPath}");
Console.WriteLine("Copied failsafe PEX/PSC files into wrapper mod.");

using var verify = SkyrimMod.CreateFromBinaryOverlay(outputPluginPath, SkyrimRelease.SkyrimSE);
var verifyQuest = verify.Quests.Records.FirstOrDefault(q => q.EditorID == QuestEditorId)
    ?? throw new InvalidOperationException("Generated plugin did not contain the wrapper quest.");

Console.WriteLine();
Console.WriteLine("Verification:");
Console.WriteLine($"  Quest:       {verifyQuest.FormKey} {verifyQuest.EditorID}");
Console.WriteLine($"  Start game:  {verifyQuest.Flags.HasFlag(Quest.Flag.StartGameEnabled)}");
Console.WriteLine($"  Scripts:     {verifyQuest.VirtualMachineAdapter?.Scripts.Count ?? 0}");
Console.WriteLine($"  Properties:  {verifyQuest.VirtualMachineAdapter?.Scripts.FirstOrDefault()?.Properties.Count ?? 0}");
Console.WriteLine($"  ESL flagged: {IsEslFlagged(outputPluginPath)}");

static FormKey FindQuest(ISkyrimModGetter mod, string editorId)
{
    return mod.Quests.Records
        .FirstOrDefault(q => string.Equals(q.EditorID, editorId, StringComparison.OrdinalIgnoreCase))
        ?.FormKey
        ?? throw new InvalidOperationException($"Could not find quest EDID '{editorId}' in Skyrim.esm.");
}

static FormKey FindGlobal(ISkyrimModGetter mod, string editorId)
{
    return mod.Globals.Records
        .FirstOrDefault(g => string.Equals(g.EditorID, editorId, StringComparison.OrdinalIgnoreCase))
        ?.FormKey
        ?? throw new InvalidOperationException($"Could not find global EDID '{editorId}' in Skyrim.esm.");
}

static FormKey FindPlacedObject(ISkyrimModGetter mod, string editorId)
{
    return mod.EnumerateMajorRecords<IPlacedObjectGetter>()
        .FirstOrDefault(p => string.Equals(p.EditorID, editorId, StringComparison.OrdinalIgnoreCase))
        ?.FormKey
        ?? throw new InvalidOperationException($"Could not find placed object EDID '{editorId}' in Skyrim.esm.");
}

static ScriptObjectProperty ObjectProperty(string name, FormKey target)
{
    var prop = new ScriptObjectProperty { Name = name };
    prop.Object.SetTo(target);
    return prop;
}

static ScriptBoolProperty BoolProperty(string name, bool value)
{
    return new ScriptBoolProperty
    {
        Name = name,
        Data = value
    };
}

static ScriptStringProperty StringProperty(string name, string value)
{
    return new ScriptStringProperty
    {
        Name = name,
        Data = value
    };
}

static void WriteSeq(string seqPath, uint localFormId)
{
    Span<byte> data = stackalloc byte[4];
    data[0] = (byte)(localFormId & 0xFF);
    data[1] = (byte)((localFormId >> 8) & 0xFF);
    data[2] = (byte)((localFormId >> 16) & 0xFF);
    data[3] = (byte)((localFormId >> 24) & 0xFF);
    File.WriteAllBytes(seqPath, data.ToArray());
}

static void SetEslFlag(string pluginPath)
{
    const uint EslFlag = 0x00000200;
    var bytes = File.ReadAllBytes(pluginPath);
    var signature = System.Text.Encoding.ASCII.GetString(bytes, 0, 4);
    if (signature != "TES4")
    {
        throw new InvalidOperationException($"Plugin '{pluginPath}' does not start with a TES4 header.");
    }

    var flags = BitConverter.ToUInt32(bytes, 8);
    flags |= EslFlag;
    Array.Copy(BitConverter.GetBytes(flags), 0, bytes, 8, 4);
    File.WriteAllBytes(pluginPath, bytes);

    if (!IsEslFlagged(pluginPath))
    {
        throw new InvalidOperationException($"Failed to set ESL flag on '{pluginPath}'.");
    }
}

static void ReplaceAsciiStringWithCp1251(string pluginPath, string oldValue, string newValue)
{
    var oldBytes = System.Text.Encoding.ASCII.GetBytes(oldValue);
    var newBytes = EncodeWindows1251(newValue);
    if (oldBytes.Length != newBytes.Length)
    {
        throw new InvalidOperationException(
            $"CP1251 replacement must match the placeholder byte length. Old={oldBytes.Length}, new={newBytes.Length}");
    }

    var bytes = File.ReadAllBytes(pluginPath);
    var match = -1;
    for (var i = 0; i <= bytes.Length - oldBytes.Length; i++)
    {
        var found = true;
        for (var j = 0; j < oldBytes.Length; j++)
        {
            if (bytes[i + j] != oldBytes[j])
            {
                found = false;
                break;
            }
        }

        if (!found)
        {
            continue;
        }

        if (match >= 0)
        {
            throw new InvalidOperationException("Found the force-delivery message placeholder more than once.");
        }

        match = i;
    }

    if (match < 0)
    {
        throw new InvalidOperationException("Could not find the force-delivery message placeholder in the generated plugin.");
    }

    Array.Copy(newBytes, 0, bytes, match, newBytes.Length);
    File.WriteAllBytes(pluginPath, bytes);
}

static byte[] EncodeWindows1251(string value)
{
    var bytes = new byte[value.Length];
    for (var i = 0; i < value.Length; i++)
    {
        var ch = value[i];
        bytes[i] = ch switch
        {
            <= '\u007F' => (byte)ch,
            '\u0401' => 0xA8,
            '\u0451' => 0xB8,
            >= '\u0410' and <= '\u044F' => (byte)(ch - 0x350),
            _ => throw new InvalidOperationException($"Character '{ch}' cannot be encoded as Windows-1251 by this helper.")
        };
    }

    return bytes;
}

static bool IsEslFlagged(string pluginPath)
{
    const uint EslFlag = 0x00000200;
    var bytes = File.ReadAllBytes(pluginPath);
    return (BitConverter.ToUInt32(bytes, 8) & EslFlag) != 0;
}

static void CopyScripts(string sourceModPath, string outputModPath)
{
    string[] scriptNames =
    [
        "WICourierFailsafeScript"
    ];

    foreach (var scriptName in scriptNames)
    {
        CopyRequired(
            Path.Combine(sourceModPath, "Scripts", scriptName + ".pex"),
            Path.Combine(outputModPath, "Scripts", scriptName + ".pex"));

        CopyRequired(
            Path.Combine(sourceModPath, "Source", "Scripts", scriptName + ".psc"),
            Path.Combine(outputModPath, "Source", "Scripts", scriptName + ".psc"));
    }
}

static void DeleteStaleAliasHelperScripts(string outputModPath)
{
    string[] staleScriptNames =
    [
        "WICourierFailsafePlayerAliasScript",
        "WICourierFailsafeCourierAliasScript"
    ];

    foreach (var scriptName in staleScriptNames)
    {
        DeleteIfExists(Path.Combine(outputModPath, "Scripts", scriptName + ".pex"));
        DeleteIfExists(Path.Combine(outputModPath, "Source", "Scripts", scriptName + ".psc"));
    }
}

static void DeleteIfExists(string path)
{
    if (File.Exists(path))
    {
        File.Delete(path);
    }
}

static void CopyRequired(string source, string destination)
{
    if (!File.Exists(source))
    {
        throw new FileNotFoundException("Required script file is missing", source);
    }

    File.Copy(source, destination, overwrite: true);
}
