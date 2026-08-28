-- Copied verbatim from benchmark/harness/seed.sql — see schema.sql's header
-- comment for why this is a literal copy, not a from-scratch tutorial seed.
--
-- Deterministic seed: the same starting state for every implementation, every
-- run. 30 users (so reporter/assignee resolution does real work, not a
-- trivial 1-2-user cache hit), one project, 200 issues spread across them.
-- 200 issues / 30 users also makes the preloading lesson's N+1 comparison
-- more dramatic than the benchmark's own 50-user number: batched preload is
-- 2 queries total regardless; unbatched is 1 + 200.
INSERT INTO users (id, email, display_name, password_hash)
SELECT
    ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
    'user' || n || '@bench.test',
    'User ' || n,
    -- A real bcrypt hash of "correct-horse-battery" — every implementation's
    -- login benchmark verifies against a real hash, not a shortcut.
    '$2b$12$K3fN2v9x8yqzXWQdVzL0FuU5m5nEo6rWQd6TzQeYqQFhLmS5aUvXW'
FROM generate_series(1, 30) AS n;

INSERT INTO projects (id, key, name, owner_id, next_issue_number)
VALUES (
    '10000000-0000-0000-0000-000000000001',
    'BENCH', 'Benchmark Project',
    '00000000-0000-0000-0000-000000000001',
    201
);

INSERT INTO issues (
    project_id, number, title, body, status, priority, reporter_id, assignee_id
)
SELECT
    '10000000-0000-0000-0000-000000000001',
    n,
    'Issue ' || n,
    'Body text for issue ' || n || ', long enough to look like a real description.',
    (ARRAY['open', 'in_progress', 'closed'])[1 + (n % 3)],
    (ARRAY['low', 'normal', 'high', 'urgent'])[1 + (n % 4)],
    ('00000000-0000-0000-0000-' || lpad(((n % 30) + 1)::text, 12, '0'))::uuid,
    CASE WHEN n % 5 = 0 THEN NULL
         ELSE ('00000000-0000-0000-0000-' || lpad((((n + 7) % 30) + 1)::text, 12, '0'))::uuid
    END
FROM generate_series(1, 200) AS n;
