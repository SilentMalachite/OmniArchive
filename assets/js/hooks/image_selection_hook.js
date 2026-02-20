// assets/js/hooks/image_selection_hook.js
// カスタム ImageSelection Hook — マウス/タッチドラッグによる範囲選択と SVG オーバーレイ
// ダブルクリック（ダブルタップ）で明示的に保存する方式

const ImageSelection = {
  mounted() {
    this.image = this.el.querySelector('#inspect-target');
    this.svg = this.el.querySelector('.crop-overlay');
    this.selectionRect = this.el.querySelector('.selection-rect');
    this.dimMask = this.el.querySelector('.dim-mask');
    this.dimCutout = this.el.querySelector('.dim-cutout');

    if (!this.image || !this.svg) return;

    // ドラッグ状態
    this.isDragging = false;
    this.startX = 0;
    this.startY = 0;

    // 現在の選択範囲（画像の自然サイズベース）
    this.selection = { x: 0, y: 0, w: 0, h: 0 };

    // 保存状態フラグ（ボーダースタイル切替用）
    this._isSaved = false;

    // ダブルタップ検出用タイムスタンプ
    this._lastTapTime = 0;

    // 画像読み込み完了後にイベントリスナーを登録
    const init = () => {
      this._setupEventListeners();
      this._loadInitialCrop();
    };

    if (this.image.complete && this.image.naturalWidth > 0) {
      init();
    } else {
      this.image.addEventListener('load', init, { once: true });
    }

    // LiveView からの Nudge イベントを処理
    this.handleEvent("nudge_crop", ({ direction, amount }) => {
      const amt = parseInt(amount, 10) || 5;
      switch (direction) {
        case "up": this.selection.y = Math.max(0, this.selection.y - amt); break;
        case "down": this.selection.y += amt; break;
        case "left": this.selection.x = Math.max(0, this.selection.x - amt); break;
        case "right": this.selection.x += amt; break;
        case "expand":
          // 各方向に amt ピクセル拡大
          this.selection.x = Math.max(0, this.selection.x - amt);
          this.selection.y = Math.max(0, this.selection.y - amt);
          this.selection.w += amt * 2;
          this.selection.h += amt * 2;
          break;
        case "shrink":
          // 各方向から amt ピクセル縮小（最小サイズ 10x10）
          this.selection.x += amt;
          this.selection.y += amt;
          this.selection.w = Math.max(10, this.selection.w - amt * 2);
          this.selection.h = Math.max(10, this.selection.h - amt * 2);
          break;
      }
      this._clampSelection();
      this._markDraft();
      this._updateOverlay();
      this._pushPreviewData();
    });

    // LiveView からの Undo/復元イベントを処理
    this.handleEvent("restore_crop", ({ crop_data }) => {
      if (crop_data) {
        this.selection = {
          x: parseInt(crop_data.x || crop_data["x"] || 0, 10),
          y: parseInt(crop_data.y || crop_data["y"] || 0, 10),
          w: parseInt(crop_data.width || crop_data["width"] || crop_data.w || crop_data["w"] || 0, 10),
          h: parseInt(crop_data.height || crop_data["height"] || crop_data.h || crop_data["h"] || 0, 10)
        };
        this._updateOverlay();
      }
    });

    // LiveView から保存成功通知を受信
    this.handleEvent("save_confirmed", () => {
      this._isSaved = true;
      this._updateSelectionStyle();
      this._flashSaveSuccess();
    });
  },

  destroyed() {
    // クリーンアップ
    this._removeEventListeners();
  },

  // 初期クロップデータがあれば読み込み、viewBox を必ず初期化
  _loadInitialCrop() {
    // viewBox を画像の自然サイズで初期化（座標系を確立）
    if (this.image && this.svg && this.image.naturalWidth > 0) {
      const nw = this.image.naturalWidth;
      const nh = this.image.naturalHeight;
      this.svg.setAttribute('viewBox', `0 0 ${nw} ${nh}`);
    }

    const dataEl = this.el.querySelector('[data-crop-x]');
    if (dataEl) {
      const x = parseInt(dataEl.dataset.cropX || 0, 10);
      const y = parseInt(dataEl.dataset.cropY || 0, 10);
      const w = parseInt(dataEl.dataset.cropW || 0, 10);
      const h = parseInt(dataEl.dataset.cropH || 0, 10);
      if (w > 0 && h > 0) {
        this.selection = { x, y, w, h };
        // DB に保存済みのデータがあれば saved 状態で表示
        this._isSaved = true;
        this._updateOverlay();
        this._updateSelectionStyle();
      }
    }
  },

  // マウス/タッチ/ダブルクリックイベントリスナーを登録
  _setupEventListeners() {
    // マウスイベント
    this._onMouseDown = (e) => this._handleStart(e, e.clientX, e.clientY);
    this._onMouseMove = (e) => this._handleMove(e, e.clientX, e.clientY);
    this._onMouseUp = (e) => this._handleEnd(e);

    // ダブルクリック → 保存
    this._onDblClick = (e) => {
      // ナッジボタンやアクションバーを除外
      if (e.target.closest('.nudge-controls') || e.target.closest('.action-bar')) return;
      e.preventDefault();
      if (this.selection.w > 5 && this.selection.h > 5) {
        this._pushSaveCrop();
      }
    };

    // タッチイベント（ROG Ally X 対応）
    this._onTouchStart = (e) => {
      if (e.touches.length === 1) {
        this._handleStart(e, e.touches[0].clientX, e.touches[0].clientY);
      }
    };
    this._onTouchMove = (e) => {
      if (e.touches.length === 1) {
        this._handleMove(e, e.touches[0].clientX, e.touches[0].clientY);
      }
    };
    this._onTouchEnd = (e) => {
      this._handleEnd(e);
      // ダブルタップ検出（300ms 以内に2回タップ）
      this._detectDoubleTap();
    };

    this.el.addEventListener('mousedown', this._onMouseDown);
    document.addEventListener('mousemove', this._onMouseMove);
    document.addEventListener('mouseup', this._onMouseUp);
    this.el.addEventListener('dblclick', this._onDblClick);

    this.el.addEventListener('touchstart', this._onTouchStart, { passive: false });
    document.addEventListener('touchmove', this._onTouchMove, { passive: false });
    document.addEventListener('touchend', this._onTouchEnd);
  },

  _removeEventListeners() {
    if (this._onMouseDown) {
      this.el.removeEventListener('mousedown', this._onMouseDown);
      document.removeEventListener('mousemove', this._onMouseMove);
      document.removeEventListener('mouseup', this._onMouseUp);
    }
    if (this._onDblClick) {
      this.el.removeEventListener('dblclick', this._onDblClick);
    }
    if (this._onTouchStart) {
      this.el.removeEventListener('touchstart', this._onTouchStart);
      document.removeEventListener('touchmove', this._onTouchMove);
      document.removeEventListener('touchend', this._onTouchEnd);
    }
  },

  // ダブルタップ検出（タッチ端末用）
  _detectDoubleTap() {
    const now = Date.now();
    const elapsed = now - this._lastTapTime;
    if (elapsed < 300 && elapsed > 0) {
      // ダブルタップ検出 → 保存
      if (this.selection.w > 5 && this.selection.h > 5) {
        this._pushSaveCrop();
      }
      this._lastTapTime = 0;
    } else {
      this._lastTapTime = now;
    }
  },

  // クライアント座標 → 画像自然サイズの相対座標に変換
  _toImageCoords(clientX, clientY) {
    const rect = this.image.getBoundingClientRect();
    const scaleX = this.image.naturalWidth / rect.width;
    const scaleY = this.image.naturalHeight / rect.height;

    const x = Math.max(0, (clientX - rect.left) * scaleX);
    const y = Math.max(0, (clientY - rect.top) * scaleY);

    return {
      x: Math.min(x, this.image.naturalWidth),
      y: Math.min(y, this.image.naturalHeight)
    };
  },

  // ドラッグ開始
  _handleStart(e, clientX, clientY) {
    // ナッジボタンのクリック等を除外
    if (e.target.closest('.nudge-controls') || e.target.closest('.action-bar')) return;

    e.preventDefault();
    this.isDragging = true;
    const coords = this._toImageCoords(clientX, clientY);
    this.startX = coords.x;
    this.startY = coords.y;
  },

  // ドラッグ中（JS側でSVGオーバーレイをリアルタイム更新、サーバー送信はドラッグ終了時のみ）
  _handleMove(e, clientX, clientY) {
    if (!this.isDragging) return;
    e.preventDefault();

    const coords = this._toImageCoords(clientX, clientY);

    // 始点と現在の座標から矩形を計算（左上と幅高さを決定）
    this.selection = {
      x: Math.round(Math.min(this.startX, coords.x)),
      y: Math.round(Math.min(this.startY, coords.y)),
      w: Math.round(Math.abs(coords.x - this.startX)),
      h: Math.round(Math.abs(coords.y - this.startY))
    };

    this._clampSelection();
    this._updateOverlay();
  },

  // ドラッグ終了 — プレビューのみ送信（DB保存なし）
  _handleEnd(_e) {
    if (!this.isDragging) return;
    this.isDragging = false;

    // 最小サイズチェック（偶発的なクリックを無視）
    if (this.selection.w > 5 && this.selection.h > 5) {
      this._markDraft();
      this._pushPreviewData();
    }
  },

  // 未保存（ドラフト）状態にマーク
  _markDraft() {
    this._isSaved = false;
    this._updateSelectionStyle();
  },

  // 選択範囲を画像の境界内にクランプ
  _clampSelection() {
    if (!this.image) return;
    const nw = this.image.naturalWidth;
    const nh = this.image.naturalHeight;

    this.selection.x = Math.max(0, Math.min(this.selection.x, nw));
    this.selection.y = Math.max(0, Math.min(this.selection.y, nh));
    this.selection.w = Math.min(this.selection.w, nw - this.selection.x);
    this.selection.h = Math.min(this.selection.h, nh - this.selection.y);
  },

  // SVG オーバーレイを更新
  _updateOverlay() {
    if (!this.svg || !this.image) return;

    const nw = this.image.naturalWidth;
    const nh = this.image.naturalHeight;

    // SVG viewBox を画像の自然サイズに合わせる
    this.svg.setAttribute('viewBox', `0 0 ${nw} ${nh}`);

    const { x, y, w, h } = this.selection;

    // 選択矩形の表示を更新
    if (this.selectionRect) {
      this.selectionRect.setAttribute('x', x);
      this.selectionRect.setAttribute('y', y);
      this.selectionRect.setAttribute('width', w);
      this.selectionRect.setAttribute('height', h);
      this.selectionRect.style.display = (w > 0 && h > 0) ? 'block' : 'none';
    }

    // マスク（暗転部分）のカットアウトを更新
    if (this.dimCutout) {
      this.dimCutout.setAttribute('x', x);
      this.dimCutout.setAttribute('y', y);
      this.dimCutout.setAttribute('width', w);
      this.dimCutout.setAttribute('height', h);
    }

    // マスク矩形のサイズ更新
    if (this.dimMask) {
      this.dimMask.setAttribute('width', nw);
      this.dimMask.setAttribute('height', nh);
    }
  },

  // 選択枠のスタイルを切替（dashed=未保存 / solid=保存済み）
  _updateSelectionStyle() {
    if (!this.selectionRect) return;
    if (this._isSaved) {
      this.selectionRect.setAttribute('stroke-dasharray', 'none');
      this.selectionRect.setAttribute('stroke', '#4CAF50');
    } else {
      this.selectionRect.setAttribute('stroke-dasharray', '8 4');
      this.selectionRect.setAttribute('stroke', '#E6B422');
    }
  },

  // 保存成功フラッシュ — 枠が一瞬 Bright Gold に光る
  _flashSaveSuccess() {
    if (!this.selectionRect) return;
    this.selectionRect.setAttribute('stroke', '#FFD700');
    this.selectionRect.setAttribute('stroke-width', '4');
    setTimeout(() => {
      this.selectionRect.setAttribute('stroke', '#4CAF50');
      this.selectionRect.setAttribute('stroke-width', '2');
    }, 600);
  },

  // プレビューデータを LiveView に送信（DB保存なし）
  _pushPreviewData() {
    this.pushEvent("preview_crop", {
      x: this.selection.x,
      y: this.selection.y,
      width: this.selection.w,
      height: this.selection.h
    });
  },

  // 保存リクエストを LiveView に送信（DB保存あり）
  _pushSaveCrop() {
    this.pushEvent("save_crop", {
      x: this.selection.x,
      y: this.selection.y,
      width: this.selection.w,
      height: this.selection.h
    });
  }
};

export default ImageSelection;
