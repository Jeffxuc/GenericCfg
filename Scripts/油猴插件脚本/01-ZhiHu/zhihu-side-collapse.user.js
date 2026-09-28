// ==UserScript==
// @name         知乎点击两侧空白处折叠回答
// @namespace    http://tampermonkey.net/
// @version      1.0
// @description  点击两侧空白收起回答和内嵌评论；图片预览时保留知乎原生关闭行为
// @author       You
// @match        https://www.zhihu.com/*
// @grant        none
// ==/UserScript==

(function () {
    'use strict';

    // 这两个图片相关类名来自你提供的实际 HTML。
    // 知乎改版后若类名变化，需要重新核对。
    const overlaySelector = [
        '.css-hr0k1l',
        'img.css-ypb3io',
        '[role="dialog"]',
        '[aria-modal="true"]',
        'dialog[open]'
    ].join(',');
    const columnSelector = '.Topstory-mainColumn, .Question-mainColumn';
    const buttonSelector = 'button, .Button, [role="button"]';
    const commentSelector = '.Comments-container, .CommentItem, .NestComment';
    let processing = false;
    let pointerStartedInOverlay = false;

    function isRendered(element) {
        if (!element.isConnected || !element.getClientRects().length) return false;
        const style = getComputedStyle(element);
        // 不排除 opacity: 0，关闭动画尚未结束时也应保护预览层。
        return style.display !== 'none' &&
            style.visibility !== 'hidden' && style.visibility !== 'collapse';
    }

    function hasOverlay(event) {
        // 即使事件过程中节点被移除，原始事件路径仍可辨认预览层。
        if (event.composedPath().some(node =>
            node instanceof Element && node.matches(overlaySelector))) return true;
        return Array.from(document.querySelectorAll(overlaySelector)).some(isRendered);
    }

    function label(button) {
        // SVG 图标旁存在零宽字符，单独 trim() 不会将它去掉。
        return (button.textContent || '').replace(/[\s\u200B-\u200D\u2060\uFEFF]/g, '');
    }

    function isSideBlank(event) {
        const target = event.target;
        if (!(target instanceof Element)) return false;
        if (target.closest('a, button, input, textarea, select, label, header, nav, aside, [role="button"], [contenteditable]:not([contenteditable="false"])')) return false;

        // 只接受承载正文栏的祖先背景，而非“所有正文以外的元素”。
        // 图片遮罩、侧栏卡片、浮动按钮等都不属于这种背景。
        return Array.from(document.querySelectorAll(columnSelector)).some(column => {
            if (!isRendered(column) || target === column || !target.contains(column)) return false;
            const rect = column.getBoundingClientRect();
            return rect.width > 0 && event.clientY >= Math.max(0, rect.top) &&
                event.clientY <= rect.bottom &&
                (event.clientX < rect.left || event.clientX > rect.right);
        });
    }

    function collapseButtons(predicate) {
        let count = 0;
        const buttons = Array.from(document.querySelectorAll(buttonSelector));
        for (const button of buttons) {
            // 每次点击前重新检查，前一个按钮可能已触发页面重新渲染。
            if (!(button instanceof HTMLElement) || !isRendered(button) ||
                button.matches(':disabled, [aria-disabled="true"]') || !predicate(button)) continue;
            button.click();
            count++;
        }
        return count;
    }

    document.addEventListener('pointerdown', function (event) {
        if (!event.isTrusted || event.button !== 0 || !event.isPrimary) return;
        // 若知乎在 pointerdown/pointerup 阶段关闭预览，随后的 click
        // 仍不得继续折叠其下方回答。
        pointerStartedInOverlay = hasOverlay(event);
    }, true);

    document.addEventListener('click', function (event) {
        // 忽略脚本自己的 button.click()，防止再次进入折叠逻辑。
        if (!event.isTrusted || event.button !== 0 || processing) return;
        const startedInOverlay = pointerStartedInOverlay;
        pointerStartedInOverlay = false;

        // 这里只退出脚本；不拦截事件、不删除图片或遮罩，
        // 让知乎自己的关闭处理器完成预览层清理。
        if (startedInOverlay || hasOverlay(event)) return;
        if (event.ctrlKey || event.altKey || event.shiftKey || event.metaKey || event.detail > 1) return;
        if (!isSideBlank(event)) return;

        processing = true;
        try {
            // 按照已确认的按钮结构，精确点击“收起评论”。
            const comments = collapseButtons(button =>
                button.matches('.ContentItem-action') && label(button) === '收起评论');

            // 评论关闭可能导致重渲染，因此重新查找回答按钮。
            // 保留原脚本收起多个回答的行为，并收紧文字和内容范围。
            const answers = collapseButtons(button =>
                label(button) === '收起' &&
                !!button.closest('.ContentItem, .RichContent') &&
                !button.closest(commentSelector));

            if (comments || answers) {
                console.log(`[知乎折叠插件] 已触发收起：评论 ${comments} 处，回答 ${answers} 条`);
            }
        } finally {
            processing = false;
        }
    }, true);
})();
