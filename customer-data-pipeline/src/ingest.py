import json
from pathlib import Path

INPUT_DIR = Path(__file__).parent / "data" / "input"


def read_jsonl(filepath: Path) -> list[dict]:
    records = []
    with open(filepath, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    return records


def main():
    customer_profiles = read_jsonl(INPUT_DIR / "customer_profile.jsonl")
    memberships = read_jsonl(INPUT_DIR / "membership.jsonl")

    print(f"Loaded {len(customer_profiles)} customer_profile records")
    print(f"Loaded {len(memberships)} membership records")


if __name__ == "__main__":
    main()
