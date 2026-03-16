// assets/js/hooks/image_selection_hook.js
// カスタム ImageSelection Hook — ポリゴン（多角形）選択モード
// シングルクリックで頂点を追加し、ダブルクリックまたは始点クリックで多角形を閉じる

const CLOSE_THRESHOLD = 20; // 始点近接判定の閾値（画像ピクセル）

const ImageSelection = {
  mounted() {
    this.image = this.el.querySelector('#inspect-target');
    this.svg = this.el.querySelector('.crop-overlay');

    if (!this.image || !this.svg) return;

    // ポリゴン頂点配列（画像の自然サイズベース）
    this.points = [];
    // ポリゴン描画中フラグ
    this.isDrawing = false;
    // ポリゴン閉じ済みフラグ
    this.isClosed = false;
    // ラバーバンド用マウス位置
    this.currentMouse = { x: 0, y: 0 };
    // 保存状態フラグ（ボーダースタイル切替用）
    this._isSaved = false;
    // ダブルタップ検出用タイムスタンプ
    this._lastTapTime = 0;
    // ダブルクリック抑制用（click イベント連鎖防止）
    this._justClosed = false;

    // SVG 要素の初期化
    this._initSvgElements();

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

    // LiveView からの Nudge イベントを処理（ポリゴン全体を平行移動）
    this.handleEvent("nudge_crop", ({ direction, amount }) => {
      if (this.points.length === 0) return;
      const amt = parseInt(amount, 10) || 5;
      let dx = 0, dy = 0;
      switch (direction) {
        case "up": dy = -amt; break;
        case "down": dy = amt; break;
        case "left": dx = -amt; break;
        case "right": dx = amt; break;
        // expand/shrink はポリゴンでは Phase 2 で対応
        default: return;
      }
      // 全頂点を平行移動
      this.points = this.points.map(p => ({
        x: Math.max(0, p.x + dx),
        y: Math.max(0, p.y + dy)
      }));
      this._clampPoints();
      this._markDraft();
      this._updateOverlay();
      this._pushPreviewData();
    });

    // LiveView からの Undo/復元イベントを処理
    this.handleEvent("restore_crop", ({ crop_data }) => {
      if (crop_data && crop_data.points) {
        this.points = crop_data.points.map(p => ({
          x: parseInt(p.x || 0, 10),
          y: parseInt(p.y || 0, 10)
        }));
        this.isClosed = true;
        this.isDrawing = false;
        this._updateOverlay();
      }
    });

    // LiveView から保存成功通知を受信
    this.handleEvent("save_confirmed", () => {
      this._isSaved = true;
      this._updatePolygonStyle();
      this._flashSaveSuccess();
    });

    // LiveView からクリアイベントを受信
    this.handleEvent("clear_polygon", () => {
      this._resetPolygon();
    });
  },

  destroyed() {
    // クリーンアップ
    this._removeEventListeners();
  },

  // SVG 要素の初期化（ポリゴン、頂点グループ、ラバーバンド線）
  _initSvgElements() {
    // 既存の dim-mask / dim-overlay 要素を取得
    this.dimMask = this.el.querySelector('.dim-mask');
    this.dimCutout = this.el.querySelector('.dim-cutout');

    // ポリゴン要素を作成（選択範囲の塗り＋枠線）
    this.polygonEl = document.createElementNS('http://www.w3.org/2000/svg', 'polygon');
    this.polygonEl.setAttribute('fill', '#E6B422');
    this.polygonEl.setAttribute('fill-opacity', '0.15');
    this.polygonEl.setAttribute('stroke', '#E6B422');
    this.polygonEl.setAttribute('stroke-width', '2');
    this.polygonEl.setAttribute('stroke-dasharray', '8 4');
    this.polygonEl.classList.add('selection-polygon');
    this.polygonEl.style.display = 'none';

    // ラバーバンド線（最終頂点 → マウス位置）
    this.rubberBand = document.createElementNS('http://www.w3.org/2000/svg', 'line');
    this.rubberBand.setAttribute('stroke', '#E6B422');
    this.rubberBand.setAttribute('stroke-width', '1.5');
    this.rubberBand.setAttribute('stroke-dasharray', '4 3');
    this.rubberBand.setAttribute('stroke-opacity', '0.7');
    this.rubberBand.style.display = 'none';

    // 頂点グループ
    this.verticesGroup = document.createElementNS('http://www.w3.org/2000/svg', 'g');
    this.verticesGroup.classList.add('polygon-vertices');

    // SVG に追加（暗転マスクの後に配置）
    this.svg.appendChild(this.polygonEl);
    this.svg.appendChild(this.rubberBand);
    this.svg.appendChild(this.verticesGroup);
  },

  // 初期クロップデータがあれば読み込み、viewBox を必ず初期化
  _loadInitialCrop() {
    // viewBox を画像の自然サイズで初期化（座標系を確立）
    if (this.image && this.svg && this.image.naturalWidth > 0) {
      const nw = this.image.naturalWidth;
      const nh = this.image.naturalHeight;
      this.svg.setAttribute('viewBox', `0 0 ${nw} ${nh}`);
    }

    // data 属性から既存の矩形クロップデータを読み込み（後方互換性）
    const dataEl = this.el.querySelector('[data-crop-x]');
    if (dataEl) {
      const x = parseInt(dataEl.dataset.cropX || 0, 10);
      const y = parseInt(dataEl.dataset.cropY || 0, 10);
      const w = parseInt(dataEl.dataset.cropW || 0, 10);
      const h = parseInt(dataEl.dataset.cropH || 0, 10);
      if (w > 0 && h > 0) {
        // 矩形データをポリゴン（4頂点）に変換
        this.points = [
          { x: x, y: y },
          { x: x + w, y: y },
          { x: x + w, y: y + h },
          { x: x, y: y + h }
        ];
        this.isClosed = true;
        this._isSaved = true;
        this._updateOverlay();
        this._updatePolygonStyle();
      }
    }
  },

  // イベントリスナーを登録
  _setupEventListeners() {
    // クリック → 頂点追加
    this._onClick = (e) => {
      // ナッジボタンやアクションバーを除外
      if (e.target.closest('.nudge-controls') || e.target.closest('.action-bar')) return;
      // ダブルクリック後の click イベントを無視
      if (this._justClosed) {
        this._justClosed = false;
        return;
      }
      e.preventDefault();
      this._addVertex(e.clientX, e.clientY);
    };

    // マウス移動 → ラバーバンド更新
    this._onMouseMove = (e) => {
      if (!this.isDrawing || this.isClosed) return;
      const coords = this._toImageCoords(e.clientX, e.clientY);
      this.currentMouse = coords;
      this._updateRubberBand();
    };

    // ダブルクリック → ポリゴンを閉じて保存
    this._onDblClick = (e) => {
      if (e.target.closest('.nudge-controls') || e.target.closest('.action-bar')) return;
      e.preventDefault();
      e.stopPropagation();

      if (this.isDrawing && this.points.length >= 3) {
        // ブラウザは dblclick の前に click を2回発火するため、
        // 誤追加された2頂点を除去（形状の "凹み" を防止）
        if (this.points.length > 3) {
          this.points = this.points.slice(0, -2);
        }
        // 描画中 → ポリゴンを閉じる
        this._closePolygon();
        this._justClosed = true;
      } else if (this.isClosed && this.points.length >= 3) {
        // 閉じ済み → 保存リクエスト
        this._pushSaveCrop();
      }
    };

    // タッチイベント
    this._onTouchStart = (e) => {
      if (e.touches.length === 1) {
        e.preventDefault();
        // ダブルタップ検出
        const now = Date.now();
        const elapsed = now - this._lastTapTime;
        if (elapsed < 300 && elapsed > 0) {
          // ダブルタップ
          if (this.isDrawing && this.points.length >= 3) {
            this._closePolygon();
          } else if (this.isClosed && this.points.length >= 3) {
            this._pushSaveCrop();
          }
          this._lastTapTime = 0;
        } else {
          this._lastTapTime = now;
          // シングルタップは遅延して頂点追加（ダブルタップかどうか判定のため）
          this._tapTimer = setTimeout(() => {
            this._addVertex(e.touches[0].clientX, e.touches[0].clientY);
          }, 310);
        }
      }
    };

    this._onTouchMove = (e) => {
      if (e.touches.length === 1 && this.isDrawing && !this.isClosed) {
        const coords = this._toImageCoords(e.touches[0].clientX, e.touches[0].clientY);
        this.currentMouse = coords;
        this._updateRubberBand();
      }
    };

    // Enterキー → ポリゴンを閉じる
    this._onKeyDown = (e) => {
      if (e.key === 'Enter' && this.isDrawing && this.points.length >= 3) {
        e.preventDefault();
        this._closePolygon();
      }
      if (e.key === 'Escape') {
        e.preventDefault();
        this._resetPolygon();
      }
    };

    this.el.addEventListener('click', this._onClick);
    this.el.addEventListener('mousemove', this._onMouseMove);
    this.el.addEventListener('dblclick', this._onDblClick);
    this.el.addEventListener('touchstart', this._onTouchStart, { passive: false });
    this.el.addEventListener('touchmove', this._onTouchMove, { passive: false });
    document.addEventListener('keydown', this._onKeyDown);
  },

  _removeEventListeners() {
    if (this._onClick) this.el.removeEventListener('click', this._onClick);
    if (this._onMouseMove) this.el.removeEventListener('mousemove', this._onMouseMove);
    if (this._onDblClick) this.el.removeEventListener('dblclick', this._onDblClick);
    if (this._onTouchStart) this.el.removeEventListener('touchstart', this._onTouchStart);
    if (this._onTouchMove) this.el.removeEventListener('touchmove', this._onTouchMove);
    if (this._onKeyDown) document.removeEventListener('keydown', this._onKeyDown);
    if (this._tapTimer) clearTimeout(this._tapTimer);
  },

  // クライアント座標 → 画像自然サイズの相対座標に変換
  _toImageCoords(clientX, clientY) {
    const rect = this.image.getBoundingClientRect();
    const scaleX = this.image.naturalWidth / rect.width;
    const scaleY = this.image.naturalHeight / rect.height;

    const x = Math.max(0, (clientX - rect.left) * scaleX);
    const y = Math.max(0, (clientY - rect.top) * scaleY);

    return {
      x: Math.round(Math.min(x, this.image.naturalWidth)),
      y: Math.round(Math.min(y, this.image.naturalHeight))
    };
  },

  // 頂点を追加
  _addVertex(clientX, clientY) {
    // 閉じ済みポリゴンをクリックした場合は何もしない（ダブルクリックで保存）
    if (this.isClosed) return;

    const coords = this._toImageCoords(clientX, clientY);

    // 最初の頂点近くをクリックした場合 → ポリゴンを閉じる
    if (this.points.length >= 3) {
      const first = this.points[0];
      const dist = Math.sqrt(
        Math.pow(coords.x - first.x, 2) + Math.pow(coords.y - first.y, 2)
      );
      if (dist < CLOSE_THRESHOLD) {
        this._closePolygon();
        return;
      }
    }

    this.points.push(coords);
    this.isDrawing = true;
    this.currentMouse = coords;

    this._updateOverlay();
  },

  // ポリゴンを閉じる
  _closePolygon() {
    if (this.points.length < 3) return;

    this.isClosed = true;
    this.isDrawing = false;

    // ラバーバンドを非表示
    this.rubberBand.style.display = 'none';

    this._markDraft();
    this._updateOverlay();
    this._pushPreviewData();
  },

  // ポリゴンをリセット
  _resetPolygon() {
    this.points = [];
    this.isDrawing = false;
    this.isClosed = false;
    this._isSaved = false;
    this.currentMouse = { x: 0, y: 0 };

    // SVG 要素をクリア
    this.polygonEl.style.display = 'none';
    this.polygonEl.setAttribute('points', '');
    this.rubberBand.style.display = 'none';
    while (this.verticesGroup.firstChild) {
      this.verticesGroup.removeChild(this.verticesGroup.firstChild);
    }
    // マスクのカットアウトもクリア
    if (this.dimCutout) {
      this.dimCutout.setAttribute('points', '');
    }
  },

  // 頂点を画像境界内にクランプ
  _clampPoints() {
    if (!this.image) return;
    const nw = this.image.naturalWidth;
    const nh = this.image.naturalHeight;
    this.points = this.points.map(p => ({
      x: Math.max(0, Math.min(p.x, nw)),
      y: Math.max(0, Math.min(p.y, nh))
    }));
  },

  // SVG オーバーレイを更新
  _updateOverlay() {
    if (!this.svg || !this.image) return;

    const nw = this.image.naturalWidth;
    const nh = this.image.naturalHeight;
    this.svg.setAttribute('viewBox', `0 0 ${nw} ${nh}`);

    // ポリゴンの points 文字列を生成
    const pointsStr = this.points.map(p => `${p.x},${p.y}`).join(' ');

    // ポリゴン要素を更新
    if (this.points.length >= 2) {
      this.polygonEl.setAttribute('points', pointsStr);
      this.polygonEl.style.display = 'block';
    } else {
      this.polygonEl.style.display = 'none';
    }

    // マスクの暗転領域にもポリゴンを反映
    if (this.dimMask) {
      this.dimMask.setAttribute('width', nw);
      this.dimMask.setAttribute('height', nh);
    }
    if (this.dimCutout && this.points.length >= 3 && this.isClosed) {
      this.dimCutout.setAttribute('points', pointsStr);
    }

    // 頂点の円を更新
    this._updateVertices();

    // ラバーバンドを更新
    this._updateRubberBand();
  },

  // 頂点の円を描画
  _updateVertices() {
    // 既存の頂点を削除
    while (this.verticesGroup.firstChild) {
      this.verticesGroup.removeChild(this.verticesGroup.firstChild);
    }

    this.points.forEach((p, i) => {
      const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
      circle.setAttribute('cx', p.x);
      circle.setAttribute('cy', p.y);

      // 始点は少し大きめに表示（クリック誘導）
      const isFirst = i === 0 && this.points.length >= 3 && !this.isClosed;
      circle.setAttribute('r', isFirst ? '8' : '5');
      circle.setAttribute('fill', isFirst ? '#FF6B6B' : '#E6B422');
      circle.setAttribute('stroke', '#fff');
      circle.setAttribute('stroke-width', '1.5');
      circle.setAttribute('fill-opacity', '0.9');

      // 始点にはホバー効果のための CSS クラスを追加
      if (isFirst) {
        circle.classList.add('start-vertex');
        circle.style.cursor = 'pointer';
      }

      this.verticesGroup.appendChild(circle);
    });
  },

  // ラバーバンド線を更新（最終頂点 → マウス位置）
  _updateRubberBand() {
    if (!this.isDrawing || this.isClosed || this.points.length === 0) {
      this.rubberBand.style.display = 'none';
      return;
    }

    const lastPoint = this.points[this.points.length - 1];
    this.rubberBand.setAttribute('x1', lastPoint.x);
    this.rubberBand.setAttribute('y1', lastPoint.y);
    this.rubberBand.setAttribute('x2', this.currentMouse.x);
    this.rubberBand.setAttribute('y2', this.currentMouse.y);
    this.rubberBand.style.display = 'block';
  },

  // 未保存（ドラフト）状態にマーク
  _markDraft() {
    this._isSaved = false;
    this._updatePolygonStyle();
  },

  // ポリゴン枠のスタイル切替（dashed=未保存 / solid=保存済み）
  _updatePolygonStyle() {
    if (!this.polygonEl) return;
    if (this._isSaved) {
      this.polygonEl.setAttribute('stroke-dasharray', 'none');
      this.polygonEl.setAttribute('stroke', '#4CAF50');
    } else {
      this.polygonEl.setAttribute('stroke-dasharray', '8 4');
      this.polygonEl.setAttribute('stroke', '#E6B422');
    }
  },

  // 保存成功フラッシュ — 枠が一瞬 Bright Gold に光る
  _flashSaveSuccess() {
    if (!this.polygonEl) return;
    this.polygonEl.setAttribute('stroke', '#FFD700');
    this.polygonEl.setAttribute('stroke-width', '4');
    setTimeout(() => {
      this.polygonEl.setAttribute('stroke', '#4CAF50');
      this.polygonEl.setAttribute('stroke-width', '2');
    }, 600);
  },

  // プレビューデータを LiveView に送信（DB保存なし）
  _pushPreviewData() {
    this.pushEvent("preview_crop", {
      points: this.points.map(p => ({ x: p.x, y: p.y }))
    });
  },

  // 保存リクエストを LiveView に送信（DB保存あり）
  _pushSaveCrop() {
    this.pushEvent("save_crop", {
      points: this.points.map(p => ({ x: p.x, y: p.y }))
    });
  }
};

export default ImageSelection;
