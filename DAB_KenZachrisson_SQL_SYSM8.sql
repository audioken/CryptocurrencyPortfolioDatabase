-- CREATE DATABASE portfolioCryptocurrency;

--------------------------------------------------------------------------------------------------------------------------------------------------
---- DROPS
--------------------------------------------------------------------------------------------------------------------------------------------------

-- DELETE EVEYTHING IN THE CORRECT ORDER
DROP PROCEDURE IF EXISTS usp_remove_coin_from_portfolio;
DROP PROCEDURE IF EXISTS usp_update_coin_in_portfolio;
DROP PROCEDURE IF EXISTS usp_add_coin_to_portfolio;
DROP PROCEDURE IF EXISTS usp_remove_coin_everywhere;
DROP PROCEDURE IF EXISTS usp_update_existing_coin;
DROP PROCEDURE IF EXISTS usp_add_new_coin;

DROP VIEW IF EXISTS view_worst_performing_investment;
DROP VIEW IF EXISTS view_best_performing_investment;
DROP VIEW IF EXISTS view_total_portfolio_value;
DROP VIEW IF EXISTS view_total_gains;
DROP VIEW IF EXISTS view_total_amount_invested;
DROP VIEW IF EXISTS view_full_portfolio;
DROP VIEW IF EXISTS view_all_coins_with_categories;

DROP TYPE IF EXISTS categoryTableType;

DROP TRIGGER IF EXISTS after_coin_from_portfolio_delete;
DROP TRIGGER IF EXISTS after_coin_from_portfolio_update;
DROP TRIGGER IF EXISTS after_coin_to_portfolio_insert;
DROP TRIGGER IF EXISTS after_coin_delete;
DROP TRIGGER IF EXISTS after_coin_update;
DROP TRIGGER IF EXISTS after_coin_insert;

DROP TABLE IF EXISTS portfolioLog;
DROP TABLE IF EXISTS coinLog;
DROP TABLE IF EXISTS coinCategory;
DROP TABLE IF EXISTS portfolio;
DROP TABLE IF EXISTS coin;
DROP TABLE IF EXISTS category;
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
---- TABLES
--------------------------------------------------------------------------------------------------------------------------------------------------

-- TABLE FOR ALL CATEGORIES
CREATE TABLE category(
    categoryID INT PRIMARY KEY IDENTITY (1,1),
    categoryName VARCHAR(50)
);
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- TABLE FOR ALL AVAILABLE CRYPTOCURRENCY COINS
CREATE TABLE coin(
    coinTicker VARCHAR(10) NOT NULL PRIMARY KEY, -- Using the coinTicker as primary key and ID since it's a suitable way to identify a coin
    coinName VARCHAR(50) NOT NULL,
    coinLaunchPrice MONEY NOT NULL CHECK (coinLaunchPrice > 0), -- Check if value is more than 0 to avoid dividebyzero error
    coinCurrentPrice MONEY NOT NULL,
    coinAllTimeLow MONEY NOT NULL,
    coinAllTimeHigh MONEY NOT NULL,

    -- ↓ AUTOMATED FIELD ↓ Calculates the return a coin has made since launch in percentage
    coinReturnSinceLaunch AS ((coinCurrentPrice / coinLaunchPrice * 100) -100) PERSISTED -- PERSISTED stores and updates the calculation directly in the table
);
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- TABLE FOR A SINGLE PORTFOLIO HOLDING COINS
CREATE TABLE portfolio(
    portfolioID INT PRIMARY KEY IDENTITY (1,1),
    coinTicker VARCHAR(10), -- RELATION: References the primary key coinTicker in the coin table to fetch coin details like category, name, and current price
    portfolioCoinHoldings DECIMAL (20,2) CHECK (portfolioCoinHoldings >= 0) DEFAULT 0, -- Check so value is more than 0 since you can't own a negative amount
    portfolioCoinEntryPrice MONEY NOT NULL CHECK (portfolioCoinEntryPrice > 0), -- Check if value is more than 0 to avoid dividebyzero error
    portfolioCoinNotes VARCHAR(255),
    FOREIGN KEY (coinTicker) REFERENCES coin(coinTicker)

    -- DERIVED VALUE: portfolioCoinROI (Return On Investment) is calculated and added via view_full_portfolio
);
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- HELPTABLE BETWEEN COIN AND CATEGORY
CREATE TABLE coinCategory(
    coinCategoryID INT PRIMARY KEY IDENTITY (1,1),
    coinCategoryCTicker VARCHAR(10),
    coinCategoryCID INT,
    FOREIGN KEY (coinCategoryCTicker) REFERENCES coin(coinTicker),
    FOREIGN KEY (coinCategoryCID) REFERENCES category(categoryID),

    -- Prevents duplicates of categories when inserting a coin
    CONSTRAINT unique_CoinCategory UNIQUE (coinCategoryCTicker, coinCategoryCID) 
);
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- LOG FOR CHANGES IN COIN-TABLE
CREATE TABLE coinLog(
    coinLogID INT PRIMARY KEY IDENTITY (1,1),
    coinLogDate DATETIME, 
    coinLogCoinName VARCHAR(50),
    coinLogInfo VARCHAR(10)
);
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- LOG FOR CHANGES IN PORTFOLIO-TABLE
CREATE TABLE portfolioLog(
    portfolioLogID INT PRIMARY KEY IDENTITY (1,1),
    portfolioLogDate DATETIME, 
    portfolioLogCoinName VARCHAR(50), 
    portfolioLogCoinAmount DECIMAL, 
    portfolioLogNetAmount MONEY, 
    portfolioLogInfo VARCHAR(10)
);
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
---- TRIGGERS
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Log an event when a new coin is inserted into the coin table
CREATE TRIGGER after_coin_insert ON coin -- Trigger is based on inserts made into the coin table
AFTER INSERT
AS
BEGIN
    INSERT INTO coinLog(
        coinLogDate, 
        coinLogCoinName,
        coinLogInfo)
    SELECT 
        GETDATE(), -- Get the current date and time
        i.coinName, -- Get the name of the coin from the insterted value
        'ADDED' -- Indicate the type of event that occured
    FROM 
        INSERTED i;
END;
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Log an event when a coin is updated in the coin table
CREATE TRIGGER after_coin_update ON coin
AFTER UPDATE
AS
BEGIN
    INSERT INTO coinLog(
        coinLogDate,
        coinLogCoinName,
        coinLogInfo)
    SELECT
        GETDATE(),
        i.coinName,
        'UPDATED'
    FROM
        INSERTED i
END;
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Log an event when a new coin is deleted from the coin table
CREATE TRIGGER after_coin_delete ON coin
AFTER DELETE
AS
BEGIN
    INSERT INTO coinLog(
        coinLogDate,
        coinLogCoinName,
        coinLogInfo)
    SELECT
        GETDATE(), 
        d.coinName, 
        'REMOVED'
    FROM 
        DELETED d;
END;
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Log an event when a coin is inserted into the portfolio table
CREATE TRIGGER after_coin_to_portfolio_insert ON portfolio
AFTER INSERT
AS
BEGIN
    INSERT INTO portfolioLog(
        portfolioLogDate,
        portfolioLogCoinName,
        portfolioLogCoinAmount,
        portfolioLogNetAmount, 
        portfolioLogInfo)
    SELECT 
        GETDATE(),
        c.coinName, -- Fetch value from join
        i.portfolioCoinHoldings,
        (i.portfolioCoinHoldings * i.portfolioCoinEntryPrice) AS portfolioLogNetAmount, -- Calculate the amount spent on coin and use AS to specify the target field
        'ADDED'
    FROM 
        INSERTED i
    JOIN
        coin c ON i.coinTicker = c.coinTicker; -- Join the coin table based on the coinTicker value from the inserted row
END;
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Log an event when a coin is updated in the portfolio table
CREATE TRIGGER after_coin_from_portfolio_update ON portfolio
AFTER UPDATE
AS
BEGIN
    INSERT INTO portfolioLog(
        portfolioLogDate,
        portfolioLogCoinName,
        portfolioLogCoinAmount,
        portfolioLogNetAmount,
        portfolioLogInfo)
    SELECT
        GETDATE(),
        c.coinName,
        i.portfolioCoinHoldings,
        (i.portfolioCoinHoldings * i.portfolioCoinEntryPrice) AS portfolioLogNetAmount,
        'UPDATED'
    FROM
        INSERTED i
    JOIN
        coin c ON i.coinTicker = c.coinTicker;
END;
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Log an event when a coin is deleted from the portfolio table
CREATE TRIGGER after_coin_from_portfolio_delete ON portfolio
AFTER DELETE
AS
BEGIN
    INSERT INTO portfolioLog(
        portfolioLogDate,
        portfolioLogCoinName,
        portfolioLogCoinAmount,
        portfolioLogNetAmount, 
        portfolioLogInfo)
    SELECT
        GETDATE(), 
        c.coinName, 
        d.portfolioCoinHoldings, 
        (d.portfolioCoinHoldings * d.portfolioCoinEntryPrice) AS portfolioLogNetAmount, 
        'REMOVED'
    FROM 
        DELETED d
    JOIN
        coin c ON d.coinTicker = c.coinTicker;
END;
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
---- INDEXES
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Create unique indexes where needed to improve performance and avoid duplicates
CREATE UNIQUE INDEX idx_unique_category ON category(categoryName);
CREATE UNIQUE INDEX idx_unique_coinTicker ON portfolio(coinTicker);
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
---- INSERTS
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Insert categories in the help table category
INSERT INTO category(categoryName)
VALUES 
    ('AI'),
    ('Layer 1'),
    ('Memecoin'),
    ('Stablecoin'),
    ('Proof Of Work'),
    ('Proof of Stake'),
    ('Real World Assets'),
    ('Decentralized Finance');
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Insert cryptocurrency coins i coin table
INSERT INTO coin(coinTicker, coinName, coinLaunchPrice, coinCurrentPrice, coinAllTimeLow, coinAllTimeHigh)
VALUES
    ('BTC', 'Bitcoin', 0.002, 85937.63, 0.002, 89864.13),
    ('ETH', 'Ethereum', 0.74, 3248.14, 0.433, 4878.26), 
    ('USDT', 'USD Tether', 1.00, 1.00, 1.00, 1.00), 
    ('PONKE', 'Ponke', 0.071399, 0.508, 0.00928, 0.7098), 
    ('ONDO', 'Ondo', 0.2195, 0.867, 0.08217, 1.48),
    ('FET', 'Artificial Superintelligence Alliance', 0.34, 1.38, 0.00817, 3.45);
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Connects cryptocurrency coins with correct categories
INSERT INTO coinCategory(coinCategoryCTicker, coinCategoryCID)
VALUES
    ('BTC', 2),     -- Bitcoin | Layer 1
    ('BTC', 5),     -- Bitcoin | Proof Of Work
    ('ETH', 2),     -- Ethereum | Layer 1
    ('ETH', 6),     -- Ethereum | Proof Of Stake
    ('USDT', 4),    -- USD Tether | Stablecoin
    ('PONKE', 3),   -- Ponke | Memecoin
    ('ONDO', 7),    -- Ondo | Real World Assets
    ('FET', 1);     -- Artificial Superintelligence Alliance | AI
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Inserts cryptocurrency coins in portfolio-table
INSERT INTO portfolio(coinTicker, portfolioCoinHoldings, portfolioCoinEntryPrice, portfolioCoinNotes)
VALUES
    ('PONKE', 6500, 0.0265, 'Love this Monkey! High risk high reward'),
    ('ONDO', 1500, 0.1, 'ICO investment'),
    ('ETH', 0.33, 1859, 'Safer bet'),
    ('FET', 357, 2.08, 'AI has potential'),
    ('USDT', 2000, 1, 'Money on the side ready for a dip in the market');
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
---- VIEWS
--------------------------------------------------------------------------------------------------------------------------------------------------

-- View all coins with categories
CREATE VIEW view_all_coins_with_categories AS
SELECT 
    STRING_AGG(ca.categoryName, ', ') AS Category, -- Use STRING_AGG to group categories for a cleaner presentation
    c.coinTicker AS Ticker,
    c.coinName AS Coin,
    CONCAT('$', c.coinLaunchPrice) AS [Launch Price], -- Use CONCAT to insert the dollar sign before a monetary value
    CONCAT('$', c.coinCurrentPrice) AS [Current Price],
    CONCAT('$', c.coinAllTimeLow) AS [All Time Low],
    CONCAT('$', c.coinAllTimeHigh) AS [All Time High],
    CONCAT(c.coinReturnSinceLaunch, '%') AS [Return Since Launch] -- Use CONCAT to insert the percentage sign after the calcuated value
FROM 
    coin c -- Fetch data from coin table
JOIN 
    coinCategory cc ON c.coinTicker = cc.coinCategoryCTicker -- Join the help table category on coinTicker ID's to access connected categories
JOIN 
    category ca ON cc.coinCategoryCID = ca.categoryID -- Join the table category on coinTicker ID's to fetch associated categories
GROUP BY
    c.coinTicker, -- ↓ Group by these fields to ensure accurate aggregation ↓
    c.coinName,
    c.coinLaunchPrice,
    c.coinCurrentPrice,
    c.coinAllTimeLow,
    c.coinAllTimeHigh,
    c.coinReturnSinceLaunch;
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- View full portfolio
CREATE VIEW view_full_portfolio AS
SELECT
    STRING_AGG(ca.categoryName, ', ') AS Category, 
    c.coinTicker AS Ticker,
    c.coinName AS [Coin Name],
    p.portfolioCoinHoldings AS Holdings,
    CONCAT('$', p.portfolioCoinEntryPrice) AS [Entry Price],
    CONCAT('$', c.coinCurrentPrice) AS [Current Price],
    CONCAT('$', CAST(p.portfolioCoinHoldings * c.coinCurrentPrice AS DECIMAL(20,2))) AS [Value], -- CAST to DECIMAL to be able to set value to 2 decimals
    CONCAT(((c.coinCurrentPrice / p.portfolioCoinEntryPrice * 100) -100), '%') AS [Return On Investment],
    p.portfolioCoinNotes AS Notes
FROM
    portfolio p -- Fetch data from portfolio table
JOIN
    coin c ON p.coinTicker = c.coinTicker -- Join coin to fetch data from coin table
JOIN
    coinCategory cc ON c.coinTicker = cc.coinCategoryCTicker -- Join help table category on coinTicker IDs
JOIN
    category ca ON cc.coinCategoryCID = ca.categoryID -- Join category to fetch data from category
GROUP BY 
    c.coinTicker, -- ↓ Group by these fields to ensure accurate aggregation ↓
    c.coinName,
    p.portfolioCoinHoldings,
    p.portfolioCoinEntryPrice,
    c.coinCurrentPrice,
    (c.coinCurrentPrice / p.portfolioCoinEntryPrice * 100) -100, -- Include full calculation for accurate aggregation
    p.portfolioCoinNotes;
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- View total amount invested and present with two decimals
CREATE VIEW view_total_amount_invested AS
SELECT
    CONCAT('$', CAST(SUM(p.portfolioCoinHoldings * p.portfolioCoinEntryPrice) AS DECIMAL(20,2))) AS [Total Investments] -- Iterates through all investments, multiplies holdings by entry price, sums the total, and formats the result.
FROM
    portfolio p; -- Fetch data from portfolio table
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- View total portfolio gains (excluding invested amount) and present with two decimals
CREATE VIEW view_total_gains AS
SELECT
    CONCAT('$', CAST(SUM(p.portfolioCoinHoldings * c.coinCurrentPrice) AS DECIMAL(20,2))
    - CAST(SUM(p.portfolioCoinHoldings * p.portfolioCoinEntryPrice) AS DECIMAL (20, 2))) AS [Total Gains]
FROM
    portfolio p
JOIN
    coin c ON p.coinTicker = c.coinTicker;
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- View total portfolio value (including invested amount) and present with two decimals
CREATE VIEW view_total_portfolio_value AS
SELECT
    CONCAT('$', CAST(SUM(p.portfolioCoinHoldings * c.coinCurrentPrice) AS DECIMAL(20,2)) 
    + CAST(SUM(p.portfolioCoinHoldings * p.portfolioCoinEntryPrice) AS DECIMAL(20,2))) AS [Total Value]
FROM
    portfolio p
JOIN
    coin c ON p.coinTicker = c.coinTicker;
GO


--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- View only the best performing coin
CREATE VIEW view_best_performing_investment AS
SELECT TOP 1 -- Select the top one coin from the result
    p.coinTicker AS [Best Performing Coin], 
    CONCAT(CAST(MAX((((c.coinCurrentPrice / p.portfolioCoinEntryPrice) * 100) - 100)) AS DECIMAL(20, 2)), '%') AS [Best ROI] -- Have to cast to limit decimals
FROM
    portfolio p
JOIN
    coin c ON p.coinTicker = c.coinTicker
GROUP BY
    p.coinTicker
ORDER BY
    MAX((((c.coinCurrentPrice / p.portfolioCoinEntryPrice) * 100) - 100)) DESC;
GO


--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- View only the worst performing coin
CREATE VIEW view_worst_performing_investment AS
SELECT TOP 1 
    p.coinTicker AS [Worst Performing Coin], 
    CONCAT(CAST(MAX((((c.coinCurrentPrice / p.portfolioCoinEntryPrice) * 100) -100)) AS DECIMAL(20,2)), '%') AS [Worst ROI]
FROM
    portfolio p
JOIN
    coin c ON p.coinTicker = c.coinTicker
GROUP BY
    p.coinTicker
ORDER BY
    MAX((((c.coinCurrentPrice / p.portfolioCoinEntryPrice) * 100) - 100)) ASC;
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
---- TYPE DEFINITIONS
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Define a table type to allow passing multiple categories as a single parameter
-- Used in procedures usp_add_new_coin and usp_update_existing_coin
CREATE TYPE categoryTableType AS TABLE (
    categoryID INT
);
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
---- STORED PROCEDURES
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Add new coin to coin-table
CREATE PROCEDURE usp_add_new_coin(
    @coinTicker VARCHAR(10),
    @coinName VARCHAR(50), 
    @coinLaunchPrice MONEY,
    @coinCurrentPrice MONEY,
    @coinAllTimeLow MONEY, 
    @coinAllTimeHigh MONEY,
    @categories categoryTableType READONLY) -- Table of categories to associate with the coin. READONLY is mandatory for the use of type definition
AS
BEGIN
    INSERT INTO coin( -- Insert the new coin into the coin table
        coinTicker, 
        coinName, 
        coinLaunchPrice, 
        coinCurrentPrice, 
        coinAllTimeLow, 
        coinAllTimeHigh)
    VALUES (
        @coinTicker, 
        @coinName, 
        @coinLaunchPrice, 
        @coinCurrentPrice, 
        @coinAllTimeLow, 
        @coinAllTimeHigh);
    
    -- Insert associated categories into the coinCategory table
    -- The categories come from the @categories table parameter
    INSERT INTO coinCategory(
        coinCategoryCTicker, 
        coinCategoryCID)
    SELECT 
        @coinTicker, 
        categoryID 
    FROM 
        @categories; -- Read the list of categories from the passed table parameter
END;
GO

-- Execute uspAddNewCoin
DECLARE @categoryList categoryTableType; -- Declare a table variable to hold the categories to be associated with the coin
INSERT INTO @categoryList (categoryID) -- Insert category IDs to link with the new coin
VALUES 
    (3), -- Add multiple categories if needed
    (4), 
    (5); 
EXEC usp_add_new_coin 
    @coinTicker = 'HEHE',
    @coinName = 'HEHE',
    @coinLaunchPrice = 0.05,
    @coinCurrentPrice = 0.56,
    @coinAllTimeLow = 0.2,
    @coinAllTimeHigh = 10,
    @categories = @categoryList;
GO

-- LIST OF CATEGORIES 
------------------------
-- 1 = AI
-- 2 = Layer 1
-- 3 = Memecoin
-- 4 = Stablecoin
-- 5 = Proof Of Work
-- 6 = Proof of Stake
-- 7 = Real World Assets
-- 8 = Decentralized Finance

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Update coin in coin-table
CREATE PROCEDURE usp_update_existing_coin(
    @coinTicker VARCHAR(10),
    @coinName VARCHAR(50), 
    @coinLaunchPrice MONEY,
    @coinCurrentPrice MONEY,
    @coinAllTimeLow MONEY, 
    @coinAllTimeHigh MONEY,
    @categories categoryTableType READONLY)
AS
BEGIN
    UPDATE 
        coin
    SET
        coinName = @coinName, 
        coinLaunchPrice = @coinLaunchPrice, 
        coinCurrentPrice = @coinCurrentPrice, 
        coinAllTimeLow = @coinAllTimeLow, 
        coinAllTimeHigh = @coinAllTimeHigh
    WHERE
        coinTicker = @coinTicker
    
    -- Update categories
    DELETE FROM coinCategory
    WHERE coinCategoryCTicker = @coinTicker;

    INSERT INTO coinCategory (coinCategoryCTicker, coinCategoryCID)
    SELECT 
        @coinTicker, categoryID
    FROM 
        @categories;
END;
GO

-- Execute uspAddNewCoin
DECLARE @categoryList categoryTableType;
INSERT INTO @categoryList (categoryID) 
VALUES 
    (7),
    (8); 
EXEC usp_update_existing_coin
    @coinTicker = 'ONDO',
    @coinName = 'Ondo',
    @coinLaunchPrice = 0.22,
    @coinCurrentPrice = 0.937,
    @coinAllTimeLow = 0.08,
    @coinAllTimeHigh = 1.48,
    @categories = @categoryList;
GO

-- LIST OF CATEGORIES 
------------------------
-- 1 = AI
-- 2 = Layer 1
-- 3 = Memecoin
-- 4 = Stablecoin
-- 5 = Proof Of Work
-- 6 = Proof of Stake
-- 7 = Real World Assets
-- 8 = Decentralized Finance

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Remove coin everywhere including portfolio
CREATE PROCEDURE usp_remove_coin_everywhere (@coinTicker VARCHAR(10))
AS
BEGIN
    -- First remove from coinCategory
    DELETE FROM coinCategory 
    WHERE coinCategory.coinCategoryCTicker = @coinTicker

    -- Then remove from portfolio
    DELETE FROM portfolio 
    WHERE portfolio.coinTicker = @coinTicker

    -- Lastly remove from coin
    DELETE FROM coin 
    WHERE coinTicker = @coinTicker;
END;
GO

-- Execute uspRemoveCoinEverywhere
EXEC usp_remove_coin_everywhere 
    @coinTicker = 'USDT';
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Add coin existing in coin-table to portfolio-table
CREATE PROCEDURE usp_add_coin_to_portfolio (
    @coinTicker VARCHAR(10),
    @portfolioCoinEntryPrice MONEY,
    @portfolioCoinHoldings DECIMAL,
    @portfolioCoinNotes VARCHAR(255))
AS
BEGIN
    -- Start a transaction to ensure data is correct
    BEGIN TRANSACTION; 
        -- Check if the coin exists in the coin table
        IF NOT EXISTS (
            SELECT 1
            FROM coin
            WHERE coin.coinTicker = @coinTicker)
        BEGIN
            -- Raise an error if the coin does not exist in the coin table
            -- RAISERROR: '16' indicates an application-level error, and '1' represents the specific state or context for this error
            RAISERROR('The coin does not excist in our coin database. Add coin first.', 16, 1);
            ROLLBACK; -- Rollback the transaction on error
            RETURN; -- Exit the procedure
        END;

        -- Check if the coin already exists in the portfolio table
        IF EXISTS (
            SELECT 1
            FROM portfolio
            WHERE portfolio.coinTicker = @coinTicker)
        BEGIN
            RAISERROR('You already have that coin in your portfolio! Please update coin in portfolio instead...', 16, 1); -- Error message if coin already exists in portfolio
            ROLLBACK
            RETURN;
        END;

        -- Insert the coin into the portfolio table
        INSERT INTO portfolio(
            coinTicker,
            portfolioCoinEntryPrice,
            portfolioCoinHoldings,
            portfolioCoinNotes )
        VALUES (
            @coinTicker,
            @portfolioCoinEntryPrice,
            @portfolioCoinHoldings,
            @portfolioCoinNotes)
    COMMIT; -- Commit the transaction after successful insertion
END;
GO

-- Execute uspAddNewCoinToPortfolio
EXEC usp_add_coin_to_portfolio 
    @coinTicker = 'HEHE', 
    @portfolioCoinEntryPrice = 0.43, 
    @portfolioCoinHoldings = 300, 
    @portfolioCoinNotes = 'Pure gambling this one..';
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Update coin in portfolio
CREATE PROCEDURE usp_update_coin_in_portfolio (
    @coinTicker VARCHAR(10),
    @portfolfioCoinHoldings DECIMAL,
    @portfolioCoinEntryPrice MONEY,
    @portfolioCoinNotes VARCHAR(255))
AS
BEGIN
    UPDATE
        portfolio 
    SET 
        portfolioCoinHoldings = @portfolfioCoinHoldings,
        portfolioCoinEntryPrice = @portfolioCoinEntryPrice,
        portfolioCoinNotes = @portfolioCoinNotes
    WHERE
        coinTicker = @coinTicker; 
END;
GO

-- Execute uspUpdateCoinInPortfolio
EXEC usp_update_coin_in_portfolio 
    @coinTicker = 'ONDO',
    @portfolfioCoinHoldings = 1000,
    @portfolioCoinEntryPrice = 0.1,
    @portfolioCoinNotes = 'ICO';
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Remove coin from portfolio
CREATE PROCEDURE usp_remove_coin_from_portfolio (
    @coinTicker VARCHAR(10))
AS
BEGIN
    DELETE FROM portfolio
    WHERE portfolio.coinTicker = @coinTicker
END;
GO

-- Execute uspRemoveCoinFromPortfolio
EXEC usp_remove_coin_from_portfolio 
    @coinTicker = 'ETH';
GO

--------------------------------------------------------------------------------------------------------------------------------------------------
---- REFERENCE INTEGRITY
--------------------------------------------------------------------------------------------------------------------------------------------------

-- -- Try to insert an already existing coin into portfolio-table
-- INSERT INTO portfolio(coinTicker, portfolioCoinHoldings, portfolioCoinEntryPrice, portfolioCoinNotes)
-- VALUES
--     ('PONKE', 1, 1, 'Test');

-- -- Try to insert a new coin with 0 in portfolioCoinEntryPrice to get warning instead of divideebyzero error
-- INSERT INTO portfolio(coinTicker, portfolioCoinHoldings, portfolioCoinEntryPrice, portfolioCoinNotes)
-- VALUES
--     ('ETH', 0, 0, 'Test');

-- -- Try to insert an already existing coin into coin-table
-- INSERT INTO coin(coinTicker, coinName, coinLaunchPrice, coinCurrentPrice, coinAllTimeLow, coinAllTimeHigh)
-- VALUES
--     ('BTC', 'Test', 1, 1, 1, 1);

-- -- Try to insert an already existing category into catagory-table
-- INSERT INTO category(categoryName)
-- VALUES 
--     ('AI');

--------------------------------------------------------------------------------------------------------------------------------------------------
---- SELECTS
--------------------------------------------------------------------------------------------------------------------------------------------------

-- Functions
SELECT * FROM view_total_amount_invested, view_total_gains, view_total_portfolio_value;
SELECT * FROM view_best_performing_investment, view_worst_performing_investment;

-- Table presentations
SELECT * FROM view_all_coins_with_categories;
SELECT * FROM view_full_portfolio;
SELECT * FROM coinLog;
SELECT * FROM portfolioLog;
SELECT * FROM category;