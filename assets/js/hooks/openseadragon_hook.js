// assets/js/hooks/openseadragon_hook.js
// OpenSeadragon Deep Zoom ビューア Hook
// IIIF Image API の info.json を使いクライアント側でタイルレンダリングを行う

import OpenSeadragon from "openseadragon"

const OpenSeadragonViewer = {
    mounted() {
        // モーダルのアニメーション完了を待ってから初期化（0x0 キャンバス問題の回避）
        this.initTimeout = setTimeout(() => {
            // data-info-url 属性から IIIF info.json URL を取得
            let rawUrl = this.el.dataset.infoUrl
            if (!rawUrl) {
                console.warn("OpenSeadragonViewer: data-info-url が未設定です")
                return
            }

            // /info.json が付与されていなければ明示的に追加（OSD が IIIF として認識するため必須）
            let infoJsonUrl = rawUrl.endsWith("/info.json") ? rawUrl : `${rawUrl}/info.json`
            console.log("OpenSeadragonViewer: tileSources =", infoJsonUrl)

            // OpenSeadragon インスタンスを初期化
            this.viewer = OpenSeadragon({
                id: this.el.id,
                tileSources: [infoJsonUrl],
                // CDN から制御アイコンを読み込み
                prefixUrl: "https://cdnjs.cloudflare.com/ajax/libs/openseadragon/4.1.0/images/",
                // ナビゲーター（ミニマップ）を右下に表示
                showNavigator: true,
                navigatorPosition: "BOTTOM_RIGHT",
                // マウスホイールでズーム
                gestureSettingsMouse: {
                    scrollToZoom: true,
                },
                // タッチデバイス対応（ピンチズーム）
                gestureSettingsTouch: {
                    pinchToZoom: true,
                },
                // アニメーション設定（スムーズなズーム）
                animationTime: 0.5,
                // ズーム制限
                minZoomLevel: 0.5,
                maxZoomLevel: 20,
                // 背景色（ダークテーマ対応）
                opacity: 1,
                // ナビゲーションボタンを表示
                showZoomControl: true,
                showHomeControl: true,
                showFullPageControl: true,
                showRotationControl: false,
            })
        }, 150) // モーダルのアニメーション完了とレイアウト確定を待機
    },

    destroyed() {
        // タイムアウトをクリア（まだ初期化前に破棄された場合）
        clearTimeout(this.initTimeout)
        // メモリリーク防止: LiveView ナビゲーション時に OSD インスタンスを破棄
        if (this.viewer) {
            this.viewer.destroy()
            this.viewer = null
        }
    },
}

export default OpenSeadragonViewer
