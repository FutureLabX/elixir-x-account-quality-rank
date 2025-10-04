# elixir-x-account-quality-rank
Ranking system for "Future for Everyone" Community

Here’s a clean `README.md` for the Elixir project you asked me to convert. It explains what the tool does, how to install, and how to run it.

---

# XProfileRanker

Elixir tool to **rank and format X (Twitter) user profiles** from a CSV dataset.
It computes engagement, activity, and follow-back scores, then outputs:

* **Markdown file** with 150 polished, story-style user entries
* **CSV file** with ranked metrics for further analysis

## Features

* Parses raw CSV exports (with typical X profile fields).
* Normalizes column names automatically.
* Enforces `following = followers_count`.
* Computes:

  * **Engagement Potential Score** (ratio-based, with emoji bars 🟦🟩🟨🟧🟥).
  * **Activity Level** (tweets per year, normalized).
  * **Chance to Follow Back** (heuristics with ratio + bio keywords).
* Generates:

  * `x_profiles_150.md` (markdown list of top 150 profiles).
  * `x_profile_ranked_top150.csv` (ranked structured data).

## Requirements

* Elixir ≥ 1.14
* Erlang/OTP ≥ 25
* Dependencies:

  * [`nimble_csv`](https://hex.pm/packages/nimble_csv)
  * [`timex`](https://hex.pm/packages/timex)

Add them in `mix.exs`:

```elixir
defp deps do
  [
    {:nimble_csv, "~> 1.2"},
    {:timex, "~> 3.7"}
  ]
end
```

## Installation

```bash
mix deps.get
```

## Usage

1. Place your CSV export at a known path (e.g., `twitter-Followers.csv`).
2. Open an IEx session:

```bash
iex -S mix
```

3. Run the tool:

```elixir
XProfileRanker.run("twitter-Followers.csv", ".")
```

This will generate two files in the current directory:

* `x_profiles_150.md` – Markdown with formatted top 150 profiles.
* `x_profile_ranked_top150.csv` – CSV with raw metrics and scores.

## Example Output (Markdown)

```markdown
1. 
@user123

   *Alex is a software engineer passionate about AI ethics.*
   - **User ID**: 1355772222447
   - **Followers**: 2.8K
   - **Following**: 2.8K
   - **Joined**: January 2021
   - **Engagement Potential Score**:
     **[🟧🟧🟧⬜⬜⬜⬜⬜⬜⬜] 30% (Low) (1:1.0)**
   - **Activity Level**:
     **[🟦🟦🟦🟦🟦🟦🟦⬜⬜⬜] 70% (Medium) | Posts: 6.3K | Media: 551**
   - **Chance to Follow Back**:
     **[🟦🟦🟦🟦🟦🟦🟦🟦🟦⬜] 90% (High)**
   - **VERIFIED**: ✅
```

## Notes

* If some fields are missing in the CSV, placeholders like `[Data unavailable]` will appear.
* The scoring thresholds are tuned to match common engagement/follow-back patterns.
* Emoji progress bars always use 10 segments.

---
