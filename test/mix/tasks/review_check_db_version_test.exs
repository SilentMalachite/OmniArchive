defmodule Mix.Tasks.Review.CheckDbVersionTest do
  # DB 接続不要の純粋なユニットテスト
  use ExUnit.Case, async: true

  alias Mix.Tasks.Review.CheckDbVersion

  describe "format_version/1" do
    # PostgreSQL 10+ の server_version_num は XXYYZZ 形式
    # XX = major, YY = minor（常に00）, ZZ = patch
    # format_version は "major.minor" を返す

    test "150004 を '15.0' に変換する（PostgreSQL 15.0, patch 4）" do
      assert CheckDbVersion.format_version(150_004) == "15.0"
    end

    test "140012 を '14.0' に変換する（PostgreSQL 14.0, patch 12）" do
      assert CheckDbVersion.format_version(140_012) == "14.0"
    end

    test "150000 を '15.0' に変換する" do
      assert CheckDbVersion.format_version(150_000) == "15.0"
    end

    test "160001 を '16.0' に変換する（PostgreSQL 16.0, patch 1）" do
      assert CheckDbVersion.format_version(160_001) == "16.0"
    end

    test "170007 を '17.0' に変換する（PostgreSQL 17.0, patch 7）" do
      assert CheckDbVersion.format_version(170_007) == "17.0"
    end

    test "180000 を '18.0' に変換する" do
      assert CheckDbVersion.format_version(180_000) == "18.0"
    end
  end
end
