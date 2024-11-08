import { defineConfig } from "drizzle-kit";
import "~~/drizzle/envConfig";

const postgresURL = process.env.POSTGRES_URL;

if (!postgresURL) {
  throw new Error("DB Url not set");
}

export default defineConfig({
  schema: "./drizzle/schema/index.ts",
  dialect: "postgresql",
  out: "./drizzle",
  dbCredentials: {
    url: postgresURL,
  },
});
