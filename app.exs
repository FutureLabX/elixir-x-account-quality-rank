# mix.exs deps:
#   {:nimble_csv, "~> 1.2"},
#   {:timex, "~> 3.7"}

defmodule XProfileRanker do
  @moduledoc false

  alias NimbleCSV.RFC4180, as: CSV
  @now ~N[2025-10-04 00:00:00]

  @emoji_blue "🟦"
  @emoji_green "🟩"
  @emoji_yellow "🟨"
  @emoji_orange "🟧"
  @emoji_red "🟥"
  @emoji_empty "⬜"

  @networking ~r/(dm|collab|network|community|open to|connect|partnership|hire|hiring|follow back|build in public)/i

  # Entry point
  def run(input_path, out_dir \\ ".") do
    rows = load_csv(input_path)

    metrics =
      rows
      |> Enum.map(&compute_metrics/1)
      |> Enum.map(&add_sort_keys/1)
      |> Enum.sort_by(&{&1.followback_pct || -1, &1.ftf || -1.0, &1.created_at_ts || -1.0}, :desc)
      |> Enum.take(150)

    md = metrics |> Enum.with_index(1) |> Enum.map(&build_markdown/1) |> Enum.join("\n\n")

    md_path = Path.join(out_dir, "x_profiles_150.md")
    File.write!(md_path, md)

    csv_path = Path.join(out_dir, "x_profile_ranked_top150.csv")
    dump_ranked_csv(csv_path, metrics)

    %{markdown: md_path, csv: csv_path}
  end

  # ---------- CSV IO ----------

  defp load_csv(path) do
    stream = File.stream!(path) |> CSV.parse_stream()
    rows = Enum.to_list(stream)
    [header | data] = rows

    headers =
      header
      |> Enum.map(&normalize_col/1)

    Enum.map(data, fn row ->
      headers
      |> Enum.zip(row)
      |> Enum.into(%{}, fn {k, v} -> {k, String.trim(to_string(v || ""))} end)
    end)
  end

  defp dump_ranked_csv(path, metrics) do
    headers = [
      "username","name","user_id","bio","created_at","tweets_count","followers","following",
      "media_count","verified","ratio_text","engagement_pct","activity_pct","tweets_per_year","followback_pct"
    ]

    rows =
      metrics
      |> Enum.map(fn m ->
        [
          m.username || "", m.name || "", m.user_id || "", m.bio || "",
          fmt_date_csv(m.created_at), to_str(m.tweets_count), to_str(m.followers),
          to_str(m.following), to_str(m.media_count), to_str(m.verified),
          m.ratio_text || "", pct_str(m.engagement_pct), pct_str(m.activity_pct),
          tpy_str(m.tweets_per_year), pct_str(m.followback_pct)
        ]
      end)

    iodata = CSV.dump_to_iodata([headers | rows])
    File.write!(path, iodata)
  end

  # ---------- Column helpers ----------

  defp normalize_col(col) do
    col
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
  end

  defp pick_col(map, candidates) do
    Enum.find(candidates, &Map.has_key?(map, &1))
  end

  # ---------- Parsing/formatting ----------

  defp to_int(nil), do: nil
  defp to_int(""), do: nil

  defp to_int(s) when is_binary(s) do
    s = String.replace(s, ",", "") |> String.trim() |> String.downcase()
    if s in ["none", "nan", "null"], do: nil, else: parse_int(s)
  end

  defp to_int(n) when is_integer(n), do: n
  defp to_int(_), do: nil

  defp parse_int(s) do
    case Integer.parse(s) do
      {i, ""} -> i
      _ ->
        case Float.parse(s) do
          {f, _} -> trunc(f)
          _ -> nil
        end
    end
  end

  defp to_bool(nil), do: false
  defp to_bool(v) when is_integer(v), do: v == 1

  defp to_bool(s) when is_binary(s) do
    case String.downcase(String.trim(s)) do
      x when x in ["true", "1", "yes", "y", "✅", "blue", "verified", "t"] -> true
      _ -> false
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(s) do
    formats = [
      "{ISO:Extended}",
      "{RFC1123}",
      "{YYYY}-{0M}-{0D} {h24}:{m}:{s}{Z:Z}",
      "{YYYY}-{0M}-{0D}",
      "{Mfull} {D}, {YYYY}"
    ]

    Enum.find_value(formats, fn fmt ->
      case Timex.parse(s, fmt) do
        {:ok, dt} -> Timex.to_naive_datetime(dt)
        _ -> nil
      end
    end)
  end

  defp fmt_month_year(nil), do: "[Data unavailable]"
  defp fmt_month_year(%NaiveDateTime{} = dt),
    do: Timex.format!(dt, "{Mfull} {YYYY}")

  defp fmt_date_csv(nil), do: ""
  defp fmt_date_csv(%NaiveDateTime{} = dt),
    do: Timex.format!(dt, "{ISO:Extended}")

  defp fmt_num(nil), do: "[Data unavailable]"
  defp fmt_num(n) when is_integer(n) and n >= 1_000_000, do: trim_trailing(:io_lib.format("~.1fM", [n / 1_000_000.0]))
  defp fmt_num(n) when is_integer(n) and n >= 1_000, do: trim_trailing(:io_lib.format("~.1fK", [n / 1_000.0]))
  defp fmt_num(n) when is_integer(n), do: Integer.to_string(n)
  defp fmt_num(_), do: "[Data unavailable]"

  defp trim_trailing(iolist) do
    s = IO.iodata_to_binary(iolist)
    case String.split(s, ".") do
      [whole, "0M"] -> whole <> "M"
      [whole, "0K"] -> whole <> "K"
      _ -> s
    end
  end

  defp pct_str(nil), do: ""
  defp pct_str(p) when is_number(p), do: :erlang.float_to_binary(p, decimals: 0)

  defp tpy_str(nil), do: ""
  defp tpy_str(f) when is_number(f), do: :erlang.float_to_binary(f, decimals: 1)

  # ---------- Scoring ----------

  defp engagement_pct(nil), do: nil
  defp engagement_pct(fpf) when is_number(fpf) do
    raw = (fpf / 10.0) * 100.0
    raw |> max(30.0) |> min(100.0)
  end

  defp activity_pct(nil, _tweets), do: nil

  defp activity_pct(%NaiveDateTime{} = created, tweets) when is_integer(tweets) do
    days = Timex.diff(@now, created, :days) |> max(1)
    years = max(0.1, days / 365.25)
    tpy = tweets / years

    pct =
      cond do
        tpy < 100 -> (tpy / 100.0) * 39.0
        tpy < 1000 -> 40.0 + ((tpy - 100.0) / 900.0) * 39.0
        true -> 80.0 + min(20.0, ((tpy - 1000.0) / 4000.0) * 20.0)
      end

    {pct, tpy}
  end

  defp activity_pct(_, _), do: {nil, nil}

  defp followback_pct(nil, _), do: nil
  defp followback_pct(_followers, nil), do: nil

  defp followback_pct(followers, following) when is_integer(followers) and is_integer(following) do
    ftf = following / max(1, followers)

    base =
      cond do
        ftf >= 1.0 -> 85
        ftf >= 0.5 -> 65
        ftf >= 0.2 -> 50
        ftf >= 0.1 -> 35
        true -> 15
      end

    {base, ftf}
  end

  defp color_for(p) when p >= 80, do: @emoji_blue
  defp color_for(p) when p >= 60, do: @emoji_green
  defp color_for(p) when p >= 40, do: @emoji_yellow
  defp color_for(p) when p >= 20, do: @emoji_orange
  defp color_for(_), do: @emoji_red

  defp bar(nil), do: {"[Data unavailable]", 0}

  defp bar(pct) do
    p = pct |> max(0.0) |> min(100.0)
    filled = round(p / 10) |> min(10) |> max(0)
    color = color_for(p)
    {String.duplicate(color, filled) <> String.duplicate(@emoji_empty, 10 - filled), round(p)}
  end

  defp label(p) when is_nil(p), do: "[Data unavailable]"
  defp label(p) when p >= 80, do: "High"
  defp label(p) when p >= 40, do: "Medium"
  defp label(_), do: "Low"

  # ---------- Row → metrics ----------

  defp compute_metrics(row) do
    col_username = pick_col(row, ~w(username screen_name user_name))
    col_name     = pick_col(row, ~w(name full_name display_name))
    col_userid   = pick_col(row, ~w(user_id id id_str))
    col_bio      = pick_col(row, ~w(bio description))
    col_created  = pick_col(row, ~w(created_at created joined))
    col_tweets   = pick_col(row, ~w(tweets_count statuses_count tweets statuses))
    col_followers_count = pick_col(row, ~w(followers_count followers))
    col_media    = pick_col(row, ~w(media_count media listed_count))
    col_verified = pick_col(row, ~w(verified is_verified))
    col_blue     = pick_col(row, ~w(blue_verify_possibly is_blue_verified blue_verified))

    username = fetch_str(row, col_username)
    name     = fetch_str(row, col_name)
    user_id  = fetch_str(row, col_userid)
    bio      = fetch_str(row, col_bio)
    created  = row |> fetch_str(col_created) |> parse_date()
    tweets   = row |> fetch_str(col_tweets) |> to_int()
    followers_cnt = row |> fetch_str(col_followers_count) |> to_int()

    # Rule: following = followers_count; followers = followers_count
    following = followers_cnt
    followers = followers_cnt

    media    = row |> fetch_str(col_media) |> to_int() || 0
    ver      = row |> fetch_str(col_verified) |> to_bool()
    blue     = row |> fetch_str(col_blue) |> to_bool()
    verified = ver or blue

    fpf =
      cond do
        is_nil(followers) or is_nil(following) or following == 0 -> nil
        true -> followers / following
      end

    eng_pct = if is_nil(fpf), do: nil, else: engagement_pct(fpf)
    ratio_text = if is_nil(fpf), do: "1:?", else: "1:#{Float.round(fpf, 1)}"

    {act_pct, tpy} = activity_pct(created, tweets)

    {fb_base, ftf} =
      case followback_pct(followers, following) do
        {b, r} -> {b, r}
        _ -> {nil, nil}
      end

    fb_adj =
      if is_nil(fb_base) do
        nil
      else
        base1 =
          if bio != nil and Regex.match?(@networking, bio), do: fb_base + 10, else: fb_base

        base2 =
          if verified and (followers || 0) > 100_000, do: base1 - 25, else: base1

        base3 =
          if (followers || 0) < 500 and (following || 0) >= 500, do: base2 + 10, else: base2

        base3 |> max(5) |> min(95)
      end

    %{
      username: username,
      name: name,
      user_id: user_id,
      bio: bio,
      created_at: created,
      tweets_count: tweets,
      followers: followers,
      following: following,
      media_count: media,
      verified: verified,
      engagement_pct: eng_pct,
      ratio_text: ratio_text,
      activity_pct: act_pct,
      tweets_per_year: tpy,
      followback_pct: fb_adj,
      ftf: ftf
    }
  end

  defp add_sort_keys(m) do
    ts =
      case m.created_at do
        %NaiveDateTime{} = dt -> NaiveDateTime.to_erl(dt) |> :calendar.datetime_to_gregorian_seconds()
        _ -> nil
      end

    Map.put(m, :created_at_ts, ts)
  end

  defp fetch_str(_map, nil), do: nil
  defp fetch_str(map, key), do: Map.get(map, key)

  # ---------- Markdown ----------

  defp build_markdown({m, idx}) do
    uname =
      cond do
        is_nil(m.username) or m.username == "" -> "[Data unavailable]"
        String.starts_with?(m.username, "@") -> m.username
        true -> "@" <> m.username
      end

    bio_intro = summarize_bio(m.name, m.bio)

    followers_disp = fmt_num(m.followers)
    following_disp = fmt_num(m.following)
    joined_disp = fmt_month_year(m.created_at)
    verified_emoji = if m.verified, do: "✅", else: "❌"

    {eng_bar, eng_pct} = bar(m.engagement_pct)
    eng_label = label(m.engagement_pct)

    {act_bar, act_pct} = bar(m.activity_pct)
    act_label = label(m.activity_pct)

    posts_disp = fmt_num(m.tweets_count)
    media_disp = fmt_num(m.media_count)

    {fb_bar, fb_pct} = bar(m.followback_pct)
    fb_label = label(m.followback_pct)

    [
      "#{idx}. ",
      uname, "\n\n",
      "   *", bio_intro, "*\n",
      "   - **User ID**: ", m.user_id || "[Data unavailable]", "\n",
      "   - **Followers**: ", followers_disp, "\n",
      "   - **Following**: ", following_disp, "\n",
      "   - **Joined**: ", joined_disp, "\n",
      "   - **Engagement Potential Score**:\n",
      "     **[", eng_bar, "] ", Integer.to_string(eng_pct), "% (", eng_label, ") (", m.ratio_text, ")**\n",
      "   - **Activity Level**:\n",
      "     **[", act_bar, "] ", Integer.to_string(act_pct), "% (", act_label, ") | Posts: ",
      posts_disp, " | Media: ", media_disp, "**\n",
      "   - **Chance to Follow Back**:\n",
      "     **[", fb_bar, "] ", Integer.to_string(fb_pct), "% (", fb_label, ")**\n",
      "   - **VERIFIED**: ", verified_emoji
    ]
    |> IO.iodata_to_binary()
  end

  defp summarize_bio(name, bio) when is_binary(bio) and byte_size(String.trim(bio)) > 0 do
    text = String.trim(bio)

    repls = [
      {~r/^i am /i, "they are "},
      {~r/^i'm /i, "they're "},
      {~r/^i /i, "they "},
      {~r/\bi am\b/i, "they are"},
      {~r/\bi'm\b/i, "they're"},
      {~r/\bmy\b/i, "their"},
      {~r/^we are /i, "they are "},
      {~r/^we /i, "they "},
      {~r/\bour\b/i, "their"}
    ]

    t =
      Enum.reduce(repls, text, fn {pat, rep}, acc ->
        Regex.replace(pat, acc, rep)
      end)

    t_short =
      case String.split(t, ".", parts: 2) do
        [first, _] -> String.trim(first)
        [only] -> String.trim(only)
      end
      |> then(fn s -> if String.length(s) > 160, do: String.slice(s, 0, 157) <> "...", else: s end)

    lead =
      case name do
        s when is_binary(s) and String.trim(s) != "" -> s
        _ -> "They"
      end

    if Regex.match?(~r/^(they|they're)\b/i, t_short),
      do: "#{lead} #{t_short}.",
      else: "#{lead} is #{t_short}."
  end

  defp summarize_bio(_name, _), do: "[No bio available]"
end
