const request = require("supertest");
const express = require("express");

// Unit test - no DB needed
const testApp = express();
testApp.get("/health", (req, res) => res.status(200).json({ status: "ok" }));

describe("GET /health", () => {
  it("returns 200", async () => {
    const res = await request(testApp).get("/health");
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe("ok");
  });
});
