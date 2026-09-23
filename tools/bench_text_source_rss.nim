## Compare retained input memory for owned text spans and shared source runs.
## Compile once, then run each mode in its own process:
##   nim c -d:release -o:/tmp/figdraw-text-rss tools/bench_text_source_rss.nim
##   /tmp/figdraw-text-rss owned
##   /tmp/figdraw-text-rss shared

import std/[os, strutils]

import figdraw/common/fonttypes

when defined(linux):
  proc rssKb(): int64 =
    for line in lines("/proc/self/status"):
      if line.startsWith("VmRSS:"):
        let fields = line.splitWhitespace()
        if fields.len >= 2:
          return parseInt(fields[1]).int64
    raise newException(IOError, "unable to read VmRSS from /proc/self/status")

elif defined(macosx):
  # Use the same task_info RSS probe as Sigils tests/trchannels.nim.
  type
    MachPort = uint32
    MachMsgTypeNumber = uint32
    TimeValue = object
      seconds: int32
      microseconds: int32

    MachTaskBasicInfo = object
      virtualSize: uint64
      residentSize: uint64
      residentSizeMax: uint64
      userTime: TimeValue
      systemTime: TimeValue
      policy: int32
      suspendCount: int32

  const machTaskBasicInfoFlavor = 20

  var machTaskSelf {.importc: "mach_task_self_", header: "<mach/mach_init.h>".}:
    MachPort

  proc taskInfo(
    task: MachPort,
    flavor: cint,
    taskInfoOut: ptr MachTaskBasicInfo,
    taskInfoOutCount: ptr MachMsgTypeNumber,
  ): cint {.importc: "task_info", header: "<mach/task.h>".}

  proc rssKb(): int64 =
    var info: MachTaskBasicInfo
    var count = MachMsgTypeNumber(sizeof(MachTaskBasicInfo) div sizeof(cuint))
    let status = taskInfo(machTaskSelf, machTaskBasicInfoFlavor, addr info, addr count)
    doAssert status == 0, "task_info failed with kern_return_t " & $status
    int64(info.residentSize div 1024)

else:
  {.error: "RSS benchmark supports Linux and macOS".}

const
  SourceBytes = 16 * 1024 * 1024
  RunBytes = 256
  RunCount = SourceBytes div RunBytes

if paramCount() != 1 or paramStr(1) notin ["owned", "shared"]:
  quit "usage: bench_text_source_rss owned|shared"

let
  mode = paramStr(1)
  source = initUtf8Runes(repeat("abcdefgh", SourceBytes div 8))
  styles = [fs(FigFont(size: 18.0'f32)), fs(FigFont(size: 19.0'f32))]
  baselineKb = rssKb()

var owned: seq[(FontStyle, string)]
var shared: seq[StyledTextRun]
if mode == "owned":
  owned = newSeqOfCap[(FontStyle, string)](RunCount)
  for index in 0 ..< RunCount:
    let start = index * RunBytes
    owned.add((styles[index mod 2], source.bytes[start ..< start + RunBytes]))
else:
  shared = newSeqOfCap[StyledTextRun](RunCount)
  for index in 0 ..< RunCount:
    let start = index * RunBytes
    shared.add StyledTextRun(
      byteStart: start.uint32,
      byteEnd: (start + RunBytes).uint32,
      runeStart: start.uint32,
      runeEnd: (start + RunBytes).uint32,
      styleId: TextStyleId(index mod 2),
    )

let retainedKb = rssKb()
echo "mode=",
  mode,
  " source_mib=",
  SourceBytes div (1024 * 1024),
  " runs=",
  max(owned.len, shared.len),
  " baseline_kib=",
  baselineKb,
  " retained_kib=",
  retainedKb,
  " input_delta_kib=",
  retainedKb - baselineKb
