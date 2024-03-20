DROP TABLE IF EXISTS metrics;
DROP TABLE IF EXISTS summary;
DROP TABLE IF EXISTS critic;
DROP TABLE IF EXISTS dependencies;
DROP TABLE IF EXISTS inheritance;
DROP TABLE IF EXISTS gitlog;
DROP TABLE IF EXISTS gitcommits;
CREATE TABLE metrics(
    id integer primary key autoincrement,
    module text, 
    subname text, 
    complexity integer, 
    lines integer
);
CREATE INDEX idx_metrics_module ON metrics (module);
CREATE TABLE summary(
    id integer primary key autoincrement,
    module text, 
    max_complexity integer, 
    lines integer, 
    pod integer, 
    avg_complexity integer, 
    sub_count integer,
    jsondata text
);
CREATE INDEX idx_summary_module ON summary (module);
CREATE TABLE critic(
    id integer primary key autoincrement, 
    module text, 
    critic text, 
    line_number integer, 
    source text, 
    explanation text
);
CREATE INDEX idx_critic_module ON critic (module);
CREATE TABLE dependencies(
    id integer primary key autoincrement, 
    module text, 
    dependencies text
);
CREATE INDEX idx_dependencies_module ON dependencies (module);
CREATE TABLE inheritance(
    id integer primary key autoincrement, 
    module text, 
    inheritance text
);
CREATE INDEX idx_inheritance_module ON inheritance (module);
CREATE TABLE role(
    id integer primary key autoincrement, 
    module text, 
    role text
);
CREATE INDEX idx_role_module ON role (module);
CREATE TABLE gitlog(
    module text, 
    latest_commit_sha text,
    log text
);
CREATE INDEX idx_gitlog_module ON gitlog (module);
CREATE TABLE gitcommits(
    date text, 
    commits integer
);
CREATE INDEX idx_gitcommits_module ON gitcommits (date);
