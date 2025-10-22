// # Node.js server for HNG Task1
const express = require("express");
const app = express();

const PORT = process.env.PORT || 3000;

app.get("/", (req, res) => {
  res.send("HNG Task1 Deployment Successful");
});

app.listen(PORT, () => {
  console.log(` Server running on port ${PORT}`);
});
