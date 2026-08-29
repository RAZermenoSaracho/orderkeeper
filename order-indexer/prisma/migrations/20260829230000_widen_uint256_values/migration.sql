-- On-chain amount and price fields are uint256 integers. NUMERIC(78,0)
-- stores that value exactly without rounding or truncation.
ALTER TABLE "Order"
ALTER COLUMN "targetPrice" TYPE DECIMAL(78,0),
ALTER COLUMN "amount" TYPE DECIMAL(78,0),
ALTER COLUMN "executionPrice" TYPE DECIMAL(78,0),
ALTER COLUMN "keeperFee" TYPE DECIMAL(78,0),
ALTER COLUMN "amountOut" TYPE DECIMAL(78,0);
