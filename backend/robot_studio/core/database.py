import aiosqlite
from robot_studio.core.config import settings


async def init_database() -> None:
    settings.data_dir.mkdir(parents=True, exist_ok=True)

    async with aiosqlite.connect(settings.database_path) as db:
        await db.execute("PRAGMA journal_mode=WAL")
        await db.execute("PRAGMA synchronous=NORMAL")
        await db.execute("PRAGMA busy_timeout=5000")
        await db.executescript(
            """
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER NOT NULL
            );

            INSERT INTO schema_version (version)
            SELECT 1
            WHERE NOT EXISTS (SELECT 1 FROM schema_version);
            """
        )
        await db.commit()


async def get_connection() -> aiosqlite.Connection:
    return await aiosqlite.connect(settings.database_path)
