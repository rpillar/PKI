CREATE TABLE metrics(module text, subname text, complexity integer, lines integer);
CREATE TABLE summary(module text, max_complexity integer, lines integer, pod integer, avg_complexity integer, sub_count integer);
CREATE TABLE critic(id integer primary key, module text, critic text, line_number integer);
CREATE TABLE dependencies(id integer primary key, module text, dependencies text);
CREATE TABLE inheritance(id integer primary key, module text, inheritance text);
