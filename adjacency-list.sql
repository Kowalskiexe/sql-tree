-- cleanup
DROP TABLE IF EXISTS adj;
DROP FUNCTION IF EXISTS rootId;
DROP PROCEDURE IF EXISTS push;
DROP PROCEDURE IF EXISTS remove;
DROP PROCEDURE IF EXISTS move;
DROP FUNCTION IF EXISTS subtree;
DROP FUNCTION IF EXISTS descendants;
DROP FUNCTION IF EXISTS ancestor;
DROP FUNCTION IF EXISTS parent;
DROP FUNCTION IF EXISTS ancestors
DROP FUNCTION IF EXISTS siblings;
DROP PROCEDURE IF EXISTS bfsCheck;
GO;
-- set up database
CREATE TABLE adj
(
    nodeId   INT NOT NULL PRIMARY KEY,
    parentId INT NULL FOREIGN KEY REFERENCES adj (nodeId),
    value    INT,
);
GO;

-- by convention root has parentId set to NULL
CREATE FUNCTION rootId()
    RETURNS INT
AS
BEGIN
    RETURN (SELECT nodeId
            FROM adj
            WHERE parentId IS NULL)
END
GO;

-- (a) adding a new node to the tree
CREATE PROCEDURE push @nodeId INT,
                      @parentId INT,
                      @value INT
AS
BEGIN
    INSERT INTO adj
    VALUES (@nodeId, @parentId, @value)
END;
GO;

-- (b) removing a specified node from the tree
CREATE PROCEDURE remove @nodeId INT
AS
BEGIN
    IF @nodeId = dbo.rootId()
        BEGIN
            DECLARE @childrenCount INT = (SELECT count(*)
                                          FROM adj
                                          WHERE parentId = @nodeid);
            IF @childrenCount > 1
                THROW 2137, 'cannot remove root', 1;
        END;

    DECLARE @parentId INT = (SELECT parentId
                             FROM adj
                             WHERE nodeId = @nodeId);

    UPDATE adj
    SET parentId = @parentId
    WHERE nodeId IN (SELECT nodeId
                     FROM adj
                     WHERE parentId = @nodeId);

    DELETE
    FROM adj
    WHERE nodeId = @nodeId;
END;
GO;

-- (c) displacement of a node in the tree
-- (displacing just the specified node, not the whole subtree)
CREATE PROCEDURE move @nodeId INT, @newParentId INT
AS
BEGIN
    DECLARE @value INT = (SELECT value
                          FROM adj
                          WHERE nodeId = @nodeId);
    EXECUTE remove @nodeId
    EXECUTE push @nodeId, @newParentId, @value
END;
GO

-- (d) getting all descendants of a node (direct and indirect)
CREATE FUNCTION subtree(@nodeId INT)
    RETURNS TABLE
        AS
        RETURN
        WITH Tree (nodeId, parentId, value, depth)
                 AS (SELECT *, 0 AS depth
                     FROM adj
                     WHERE nodeId = @nodeId
                     UNION ALL
                     SELECT c.*, ct.depth + 1 AS depth
                     FROM Tree ct
                              JOIN Adj c ON (ct.nodeId = c.parentId))
        SELECT *
        FROM Tree;
GO;

-- (e) getting node's descendants on a given depth (e.g. node's
-- grandchildren)
CREATE FUNCTION descendants(@nodeId INT, @depth INT)
    RETURNS TABLE
        AS
        RETURN SELECT *
               FROM subtree(@nodeId)
               WHERE depth = @depth;
GO;

-- (f) getting node's direct ancestor (parent)
CREATE FUNCTION parent(@nodeId INT)
    RETURNS INT
AS
BEGIN
    RETURN (SELECT parentId
            FROM adj
            WHERE nodeId = @nodeId);
END
GO;

-- (g) getting all ancestors of a given node (path to root)
CREATE FUNCTION ancestors(@nodeId INT)
    RETURNS TABLE
        AS
        RETURN
        WITH anc (nodeId, parentId, value, distance)
                 AS (SELECT *, 1 as distance
                     FROM adj
                     WHERE nodeId = (SELECT parentId
                                     FROM adj
                                     WHERE nodeId = @nodeId)
                     UNION ALL
                     SELECT c.nodeId, c.parentId, c.value, n.distance + 1
                     FROM adj c
                              JOIN anc n ON c.nodeId = n.parentId)
        SELECT *
        FROM anc;
;
GO;

-- (h) getting node's ancestor on a given level
CREATE FUNCTION ancestor(@nodeId INT, @distance INT)
    RETURNS INT
AS
BEGIN
    RETURN (SELECT nodeId
            FROM ancestors(@nodeId)
            WHERE distance = @distance)
END;
GO;

-- (i) getting all "siblings" nodes (other nodes on the same depth)
CREATE FUNCTION siblings(@nodeId INT)
    RETURNS TABLE
        AS
        RETURN
        SELECT *
        FROM subtree(dbo.root())
        WHERE depth = (SELECT COUNT(*) FROM ancestors(@nodeId))
GO;

-- (j) verification that the tree does not contain cycles
-- (k) verification that the tree is connected
-- Both these tasks can be accomplished via a breadth first search
-- traversal from the root node. After the traversal if some nodes are
-- left unvisited then that indicates that the tree is disconnected
-- and therefore corrupt.
-- In this implementation for every node except the root there is
-- exactly one edge (to its parent) so there is always exactly n nodes
-- and n-1 edges. From this we can conclude that checking for
-- connectivity is sufficient to determine if the graph is acyclic.
-- If the graph is connected then it's also acyclic.
-- If the graph is disconnected then there might be cycle but it's not
-- guaranteed.
CREATE PROCEDURE bfsCheck @passed BIT OUTPUT
AS
BEGIN
    DECLARE @row TABLE
                 (
                     nodeId INT
                 );
    DECLARE @newRow TABLE
                    (
                        nodeId INT
                    );
    DECLARE @visited TABLE
                     (
                         nodeId INT
                     );
    INSERT INTO @row
    SELECT nodeId
    FROM adj
    WHERE nodeId = dbo.rootId();

    INSERT INTO @visited
    SELECT *
    FROM @row;

    WHILE EXISTS (SELECT 1 FROM @row)
        BEGIN
            DELETE FROM @newRow WHERE 1 = 1;
            INSERT INTO @newRow
            SELECT nodeId
            FROM adj
            WHERE parentId IN (SELECT * FROM @row);

            DELETE FROM @row WHERE 1 = 1;
            IF (SELECT count(*) FROM @newRow) < 10
                INSERT INTO @row
                SELECT *
                FROM @newRow;

            INSERT INTO @visited
            SELECT *
            FROM @row;
        END;
    DECLARE @matchings TABLE
                       (
                           target INT,
                           match  INT
                       );
    INSERT INTO @matchings
    SELECT a.nodeId AS target, v.nodeId AS match
    FROM adj a
             LEFT JOIN @visited v ON a.nodeId = v.nodeId;
    IF EXISTS (SELECT 1
               FROM @matchings
               WHERE match IS NULL)
        SET @passed = 0;
    ELSE
        SET @passed = 1;
END;
GO;

-- DEMO USAGE
-- (a) adding a new node to the tree
EXEC push 1, NULL, 0;
EXEC push 2, 1, 6;
EXEC push 3, 1, 7;
EXEC push 4, 3, 3;
EXEC push 5, 3, 33;
EXEC push 6, 3, 333;
EXEC push 7, 5, 55;
EXEC push 8, 6, 66;
--        1:0
--      /  |
--  2:6   3:7
--      /   |  \
--   4:3  5:33  6:333
--          |   |
--        7:55  8:66
SELECT *
FROM adj;

-- (b) removing a specified node from the tree
EXEC remove 6
SELECT *
FROM adj;

-- (c) displacement of a node in the tree
EXEC move 8, 2
SELECT *
FROM adj;

-- (d) getting all descendants of a node (direct and indirect)
SELECT *
FROM subtree(3);

-- (e) getting node's descendants on a given depth (e.g. node's
-- grandchildren
SELECT *
FROM descendants(3, 2);

-- (f) getting node's direct ancestor (parent)
SELECT dbo.parent(3) AS [direct ancestor];

-- (g) getting all ancestors of a given node (path to root)
SELECT *
FROM ancestors(7);

-- (h) getting node's ancestor on a given level (e.g. node's
-- grandparent)
SELECT dbo.ancestor(7, 2) [ancestor on level 2];

-- (i) getting all "siblings" nodes (other nodes on the same depth)
SELECT *
FROM siblings(4);

-- (j) verification that the tree does not contain cycles
-- (k) verification that the tree is connected
-- connected and acyclic
DECLARE @passed BIT
EXEC bfsCheck @passed OUTPUT;
IF @passed = 1
    SELECT 'passed' AS [bfs check result];
ELSE
    SELECT 'did not pass' AS [bfs check result];
-- disconnected and may contain cycles
EXEC push 9, 9, 13;
EXEC bfsCheck @passed OUTPUT;
IF @passed = 1
    SELECT 'passed' AS [bfs check result];
ELSE
    SELECT 'did not pass' AS [bfs check result];
