defmodule OmniArchive.Pipeline.ResourceMonitorTest do
  @moduledoc """
  ResourceMonitor GenServer のテスト。

  アプリケーション起動時に自動起動されるため、
  実行中の GenServer に対して API を呼び出してテストします。
  """
  use ExUnit.Case, async: true

  alias OmniArchive.Pipeline.ResourceMonitor

  describe "system_info/0" do
    test "必要なキーを含むマップを返す" do
      info = ResourceMonitor.system_info()

      assert is_map(info)
      assert Map.has_key?(info, :cpu_cores)
      assert Map.has_key?(info, :total_memory_bytes)
      assert Map.has_key?(info, :available_memory_bytes)
      assert Map.has_key?(info, :pipeline_concurrency)
      assert Map.has_key?(info, :max_ptif_workers)
      assert Map.has_key?(info, :detected_at)
    end

    test "CPU コア数が正の整数である" do
      info = ResourceMonitor.system_info()

      assert is_integer(info.cpu_cores)
      assert info.cpu_cores > 0
    end

    test "メモリ値が非負の整数である" do
      info = ResourceMonitor.system_info()

      assert is_integer(info.total_memory_bytes)
      assert info.total_memory_bytes >= 0

      assert is_integer(info.available_memory_bytes)
      assert info.available_memory_bytes >= 0
    end

    test "detected_at が DateTime である" do
      info = ResourceMonitor.system_info()

      assert %DateTime{} = info.detected_at
    end
  end

  describe "pipeline_concurrency/0" do
    test "正の整数を返す" do
      concurrency = ResourceMonitor.pipeline_concurrency()

      assert is_integer(concurrency)
      assert concurrency >= 1
    end

    test "CPU コア数 - 1 以下の値を返す（UI 用に1コア確保）" do
      info = ResourceMonitor.system_info()
      concurrency = ResourceMonitor.pipeline_concurrency()

      # max(cpu_cores - 1, 1) のロジックに基づく
      expected = max(info.cpu_cores - 1, 1)
      assert concurrency == expected
    end

    test "シングルコア環境でも最低1を返す" do
      concurrency = ResourceMonitor.pipeline_concurrency()

      # どのような環境でも最低1が保証される
      assert concurrency >= 1
    end
  end

  describe "max_ptif_workers/0" do
    test "正の整数を返す" do
      workers = ResourceMonitor.max_ptif_workers()

      assert is_integer(workers)
      assert workers >= 1
    end

    test "pipeline_concurrency 以下の値を返す" do
      workers = ResourceMonitor.max_ptif_workers()
      concurrency = ResourceMonitor.pipeline_concurrency()

      # メモリガードにより、CPU制限とメモリ制限の小さい方を採用
      assert workers <= concurrency
    end
  end

  describe "リソース整合性" do
    test "利用可能メモリが総メモリを超えない" do
      info = ResourceMonitor.system_info()

      # 正常な環境では利用可能メモリ <= 総メモリ
      if info.total_memory_bytes > 0 do
        assert info.available_memory_bytes <= info.total_memory_bytes
      end
    end

    test "並列度とワーカー数が整合している" do
      info = ResourceMonitor.system_info()

      assert info.pipeline_concurrency >= 1
      assert info.max_ptif_workers >= 1
      assert info.max_ptif_workers <= info.pipeline_concurrency
    end
  end
end
