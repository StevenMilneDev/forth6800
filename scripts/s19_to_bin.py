#!/usr/bin/env python3
import argparse
from pathlib import Path


def parse_srec_line(line: str):
    line = line.strip()
    if not line or not line.startswith("S"):
        return None
    rectype = line[1]
    if rectype not in {"1", "2", "3"}:
        return None

    count = int(line[2:4], 16)
    payload = bytes.fromhex(line[4:])
    if len(payload) != count:
        raise ValueError(f"Invalid count for record: {line}")

    if rectype == "1":
        addr_len = 2
    elif rectype == "2":
        addr_len = 3
    else:
        addr_len = 4

    addr = int.from_bytes(payload[:addr_len], "big")
    data = payload[addr_len:-1]

    checksum = payload[-1]
    calc = (~((count + sum(payload[:-1])) & 0xFF)) & 0xFF
    if checksum != calc:
        raise ValueError(f"Checksum mismatch in record: {line}")

    return addr, data


def s19_to_bin(s19_path: Path, out_path: Path):
    segments = []
    with s19_path.open("r", encoding="utf-8", errors="ignore") as f:
        for raw_line in f:
            rec = parse_srec_line(raw_line)
            if rec:
                segments.append(rec)

    if not segments:
        raise ValueError("No S1/S2/S3 data records found")

    start = min(addr for addr, _ in segments)
    end = max(addr + len(data) for addr, data in segments)
    image = bytearray([0xFF] * (end - start))

    for addr, data in segments:
        off = addr - start
        image[off:off + len(data)] = data

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(image)
    return start, end, len(image)


def main():
    parser = argparse.ArgumentParser(description="Convert Motorola S-record (.s19) to contiguous binary image")
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    start, end, size = s19_to_bin(args.input, args.output)
    print(f"Wrote {args.output} ({size} bytes, address range ${start:04X}-${end - 1:04X})")


if __name__ == "__main__":
    main()
