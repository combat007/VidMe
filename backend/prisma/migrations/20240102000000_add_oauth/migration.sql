-- Make password nullable (OAuth users have no password)
ALTER TABLE "User" ALTER COLUMN "password" DROP NOT NULL;

-- Add OAuth provider columns
ALTER TABLE "User" ADD COLUMN "googleId" TEXT;
ALTER TABLE "User" ADD COLUMN "githubId" TEXT;
ALTER TABLE "User" ADD COLUMN "name"     TEXT;

-- Unique indexes for provider IDs
CREATE UNIQUE INDEX "User_googleId_key" ON "User"("googleId") WHERE "googleId" IS NOT NULL;
CREATE UNIQUE INDEX "User_githubId_key" ON "User"("githubId") WHERE "githubId" IS NOT NULL;
