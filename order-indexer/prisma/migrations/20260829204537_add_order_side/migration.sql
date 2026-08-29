/*
  MVP deployment note:

  This migration intentionally targets a fresh or reset indexer database.
  Legacy rows describe an obsolete contract deployment whose `asset` field
  cannot be truthfully converted into the current Buy/Sell `side` semantics.
  Follow RUNBOOK.md's fresh-database/reset workflow instead of applying this
  migration to a populated legacy database.

  Warnings:

  - You are about to drop the column `asset` on the `Order` table. All the data in the column will be lost.
  - Added the required column `side` to the `Order` table without a default value. This is not possible if the table is not empty.

*/
-- CreateEnum
CREATE TYPE "OrderSide" AS ENUM ('Sell', 'Buy');

-- AlterTable
ALTER TABLE "Order" DROP COLUMN "asset",
ADD COLUMN     "side" "OrderSide" NOT NULL;
