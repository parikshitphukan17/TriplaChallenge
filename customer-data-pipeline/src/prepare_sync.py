import duckdb
from pathlib import Path

DB_PATH = Path(__file__).parent / "db" / "pipeline.duckdb"
OUTPUT_DIR = Path(__file__).parent / "data" / "output"


def read_from_db(conn: duckdb.DuckDBPyConnection) -> tuple[list[dict], list[dict]]:
    pass


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    conn = duckdb.connect(str(DB_PATH))

    customer_profiles, memberships = read_from_db(conn)
    conn.close()

    print(f"Loaded {len(customer_profiles)} current customer_profile records")
    print(f"Loaded {len(memberships)} current membership records")


if __name__ == "__main__":
    main()
