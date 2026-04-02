CREATE TABLE IF NOT EXISTS courses (
    id   TEXT PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS activities (
    id           TEXT PRIMARY KEY,
    title        TEXT NOT NULL,
    course_id    TEXT NOT NULL,
    due_date     TEXT,
    status       TEXT NOT NULL DEFAULT 'pending',
    url          TEXT,
    score        TEXT,
    description  TEXT,
    last_updated TEXT NOT NULL,
    FOREIGN KEY (course_id) REFERENCES courses(id)
);
