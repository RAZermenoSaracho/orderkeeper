-- CreateEnum
CREATE TYPE "PriceCondition" AS ENUM ('GreaterOrEqual', 'LessOrEqual');

-- CreateEnum
CREATE TYPE "OrderStatus" AS ENUM ('Pending', 'Executed', 'Cancelled');

-- CreateTable
CREATE TABLE "Order" (
    "orderId" INTEGER NOT NULL,
    "owner" TEXT NOT NULL,
    "asset" TEXT NOT NULL,
    "condition" "PriceCondition" NOT NULL,
    "targetPrice" DECIMAL(65,30) NOT NULL,
    "amount" DECIMAL(65,30) NOT NULL,
    "maxSlippageBps" INTEGER NOT NULL,
    "expiry" TIMESTAMP(3) NOT NULL,
    "status" "OrderStatus" NOT NULL DEFAULT 'Pending',
    "createdAtBlock" BIGINT NOT NULL,
    "createdAtTx" TEXT NOT NULL,
    "executedAtBlock" BIGINT,
    "executedAtTx" TEXT,
    "executionPrice" DECIMAL(65,30),
    "keeperFee" DECIMAL(65,30),
    "amountOut" DECIMAL(65,30),
    "cancelledAtBlock" BIGINT,
    "cancelledAtTx" TEXT,
    "indexedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Order_pkey" PRIMARY KEY ("orderId")
);

-- CreateTable
CREATE TABLE "IndexerState" (
    "id" INTEGER NOT NULL DEFAULT 1,
    "lastProcessedBlock" BIGINT NOT NULL,

    CONSTRAINT "IndexerState_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Order_status_idx" ON "Order"("status");
