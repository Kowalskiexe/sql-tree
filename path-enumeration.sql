-- cleanup
DROP TABLE IF EXISTS pe;
DROP FUNCTION IF EXISTS countOccurrences;
DROP FUNCTION IF EXISTS depth;
DROP FUNCTION IF EXISTS relpath;
DROP PROCEDURE IF EXISTS push;
DROP FUNCTION IF EXISTS descendants;
DROP FUNCTION IF EXISTS descendants2;
DROP FUNCTION IF EXISTS parent;
DROP FUNCTION IF EXISTS ancestors;
DROP FUNCTION IF EXISTS ancestors2;
DROP FUNCTION IF EXISTS siblings;
DROP PROCEDURE IF EXISTS checkIntegrity;
DROP PROCEDURE IF EXISTS remove;
DROP PROCEDURE IF EXISTS move;
DROP TYPE IF EXISTS patht;
GO;
CREATE TYPE patht
    FROM VARCHAR(1000);
GO;

-- setup database
CREATE TABLE pe
(
    path  patht PRIMARY KEY,
    value INT
);
GO;

-- By convention '/' is the separator.

CREATE FUNCTION countOccurrences(@text patht, @pattern patht)
    RETURNS INT
AS
BEGIN
    DECLARE @output INT = (SELECT (len(@text) - len(replace(@text, @pattern, ''))) / len(@pattern));
    RETURN @output;
END
GO;

CREATE FUNCTION depth(@path patht)
    RETURNS INT
AS
BEGIN
    DECLARE @output INT = dbo.countOccurrences(@path, '/');
    RETURN @output;
END;
GO;

CREATE FUNCTION relpath(@parentPath patht, @descendantPath patht)
    RETURNS patht
AS
BEGIN
    DECLARE @output patht = (SELECT right(@descendantPath, len(@descendantPath) - len(@parentPath) - 1));
    RETURN @output;
END;
GO;


-- (a) adding a new node to the tree
CREATE PROCEDURE push @path patht, @value INT
AS
BEGIN
    INSERT INTO pe
    VALUES (@path, @value);
END;
GO;

-- (d) getting all descendants of a node (direct and indirect)
CREATE FUNCTION descendants(@path patht)
    RETURNS TABLE
        AS
        RETURN SELECT *
               FROM pe
               WHERE path LIKE concat(@path, '/%');
GO;

-- (e) getting node's descendants on a given depth (e.g. node's
-- grandchildren)
CREATE FUNCTION descendants2(@path patht, @distance INT)
    RETURNS TABLE
        AS
        RETURN
        SELECT path, value
        FROM (SELECT *, dbo.depth(relpath) + 1 AS distance
              FROM (SELECT *, dbo.relpath(@path, path) AS relpath
                    FROM descendants(@path)) AS t) as t2
        WHERE distance = @distance;
GO;

-- (f) getting node's direct ancestor (parent)
CREATE FUNCTION parent(@path patht)
    RETURNS patht
AS
BEGIN
    DECLARE @output patht = reverse(@path);
    DECLARE @last INT = charindex('/', @output);
    SET @output = left(@path, len(@path) - @last);
    RETURN @output;
END;
GO;

-- (g) getting all ancestors of a given node (path to root)
CREATE FUNCTION ancestors(@path patht)
    RETURNS TABLE
        AS
        RETURN
        WITH CTE(path, value)
                 AS (SELECT *
                     FROM pe
                     WHERE path = dbo.parent(@path)
                     UNION ALL
                     SELECT c.path, c.value
                     FROM pe c
                              JOIN CTE n ON c.path = dbo.parent(n.path) AND dbo.depth(n.path) > 0)
        SELECT *
        FROM CTE;
GO;

-- (h) getting node's ancestor on a given level
CREATE FUNCTION ancestors2(@path patht, @distance INT)
    RETURNS TABLE
        AS
        RETURN SELECT path, value
               FROM (SELECT *, dbo.depth(@path) - dbo.depth(path) AS distance
                     FROM ancestors(@path)) AS t
               WHERE distance = @distance;
GO;

-- (i) getting all "siblings" nodes (other nodes on the same depth)
CREATE FUNCTION siblings(@path patht)
    RETURNS TABLE
        AS
        RETURN SELECT path, value
               FROM (SELECT *, dbo.depth(path) AS depth
                     FROM pe) AS t
               WHERE depth = dbo.depth(@path)
                 AND path <> @path;
GO;

-- (k) verification that the tree is connected
-- In order for the tree to be connected, every node except root must have a valid parent.
CREATE PROCEDURE checkIntegrity @passed BIT OUTPUT
AS
BEGIN
    -- tree must have exactly one root
    IF (SELECT count(*)
        FROM pe
        WHERE dbo.depth(path) = 0) <> 1
        BEGIN
            SET @passed = 0;
            RETURN;
        END;


    DECLARE @integrityTable TABLE
                            (
                                path           patht,
                                ancestorsCount INT,
                                depth          INT
                            );
    INSERT INTO @integrityTable
    SELECT pe.path, ISNULL(ancestorsCount, 0) AS ancestorsCount, dbo.depth(pe.path) AS depth
    FROM pe
             LEFT JOIN (SELECT pe.path, count(*) AS ancestorsCount
                        FROM pe
                                 CROSS APPLY ancestors(pe.path) a
                        WHERE pe.path <> a.path
                        GROUP BY pe.path) AS t ON pe.path = t.path;

    IF exists(SELECT 1 FROM @integrityTable WHERE ancestorsCount <> depth)
        SET @passed = 0;
    ELSE
        SET @passed = 1;
END;
GO;

-- (b) removing a specified node from the tree
CREATE PROCEDURE remove @path patht
AS
BEGIN
    -- get descendants
    DECLARE @d TABLE
               (
                   path patht
               );
    INSERT INTO @d
    SELECT path
    FROM descendants(@path);
    -- remove node
    DELETE
    FROM pe
    WHERE path = @path;
    -- shorten descendants paths
    UPDATE pe
    SET path = concat(dbo.parent(@path), '/', dbo.relpath(@path, path))
    WHERE path IN (SELECT * FROM @d);
END;
GO;

-- (c) displacement of a node in the tree
CREATE PROCEDURE move @path patht, @newPath patht
AS
BEGIN
    DECLARE @value INT = (SELECT value FROM pe WHERE path = @path);
    EXEC remove @path;
    EXEC push @newPath, @value;
END;
GO;

-- DEMO USAGE
-- (a) adding a new node to the tree
--        1:0
--      /  |
--  2:6   3:7
--      /   |  \
--   4:3  5:33  6:333
--          |   |
--        7:55  8:66
EXEC push '1', 0;
EXEC push '1/2', 6;
EXEC push '1/3', 7;
EXEC push '1/3/4', 3;
EXEC push '1/3/5', 33;
EXEC push '1/3/6', 333;
EXEC push '1/3/5/7', 55;
EXEC push '1/3/6/8', 66;
SELECT *
FROM pe;

-- (b) removing a specified node from the tree
EXEC remove '1/3/6';
SELECT *
FROM pe;

-- (c) displacement of a node in the tree
EXEC move '1/3/8', '1/2/8';
SELECT *
FROM pe;

-- (d) getting all descendants of a node (direct and indirect)
SELECT *
FROM descendants('1/3');

-- (e) getting node's descendants on a given depth (e.g. node's
-- grandchildren
SELECT *
FROM descendants2('1/3', 2);

-- (f) getting node's direct ancestor (parent)
SELECT dbo.parent('1/3/6') AS [direct ancestor];

-- (g) getting all ancestors of a given node (path to root)
SELECT *
FROM ancestors('1/3/6');

-- (h) getting node's ancestor on a given level (e.g. node's
-- grandparent)
SELECT *
FROM ancestors2('1/3/6', 2);

-- (i) getting all "siblings" nodes (other nodes on the same depth)
SELECT *
FROM siblings('1/3/6');

-- (j) verification that the tree does not contain cycles
SELECT N'This implementation is cycle-free. A cycle would require an infinite path.' AS cycles

-- (k) verification that the tree is connected
DECLARE @passed BIT;
-- connected tree
EXEC checkIntegrity @passed OUTPUT;
IF @passed = 1
    -- k) connected
    SELECT N'Check 1: connected tree :)' AS result;
ELSE
    SELECT N'Check 1: disconnected tree :(' AS result;
-- corrupt, disconnected tree
EXEC push '1/100/23', 107;
EXEC checkIntegrity @passed OUTPUT;
IF @passed = 1
    SELECT N'Check 2: connected tree :)' AS result;
ELSE
    SELECT N'Check 2: disconnected tree :(' AS result;
