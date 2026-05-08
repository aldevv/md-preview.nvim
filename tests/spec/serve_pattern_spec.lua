describe("clear_stale_server cmdline match", function()
  local pattern = "mdp%s+serve"

  local matches = {
    "mdp serve /tmp/file.md 9753 dark",
    "/home/u/.local/bin/mdp serve a b c",
    "./mdp\tserve x y z",
    "/usr/local/bin/mdp  serve foo 1 light",
  }
  for _, cmd in ipairs(matches) do
    it("matches: " .. cmd, function()
      assert(cmd:match(pattern), "expected match: " .. cmd)
    end)
  end

  local non_matches = {
    "nvim cmd/mdp/serve.go",
    "python3 md-preview-server.py f 9753 dark",
    "mdpfoobar",
    "less mdp_serve.txt",
    "go build ./cmd/mdp",
  }
  for _, cmd in ipairs(non_matches) do
    it("does not match: " .. cmd, function()
      assert(not cmd:match(pattern), "expected no match: " .. cmd)
    end)
  end
end)
