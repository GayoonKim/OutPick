import type {Page} from "playwright";

export async function inspectDiscoveryPageControls(
  page: Page, clickLoadMore = false,
): Promise<{loadMoreDetected: boolean;
  forwardPaginationDetected: boolean; clicked: boolean}> {
  return page.evaluate(({patternSource, click}) => {
    type BrowserElement = {
      innerText?: string; textContent?: string | null;
      getAttribute: (name: string) => string | null;
      hasAttribute: (name: string) => boolean;
      getBoundingClientRect: () => {width: number; height: number};
      click: () => void;
    };
    const browser = globalThis as unknown as {
      location: {href: string};
      document: {
        querySelectorAll: (selector: string) => ArrayLike<BrowserElement>;
      };
      getComputedStyle: (element: BrowserElement) => {
        display: string; visibility: string; pointerEvents: string;
      };
    };
    const usable = (element: BrowserElement) => {
      const rect = element.getBoundingClientRect();
      const style = browser.getComputedStyle(element);
      return !element.hasAttribute("disabled") &&
        element.getAttribute("aria-disabled") !== "true" &&
        rect.width > 0 && rect.height > 0 && style.display !== "none" &&
        !["hidden", "collapse"].includes(style.visibility) &&
        style.pointerEvents !== "none";
    };
    const text = (element: BrowserElement) =>
      (element.innerText || element.textContent || "").trim();
    const pattern = new RegExp(patternSource, "i");
    const more = Array.from(browser.document.querySelectorAll(
      "button,a,[role='button']")).find((element) => usable(element) &&
      (pattern.test(text(element)) ||
        pattern.test(element.getAttribute("aria-label") || "") ||
        /more|load|view_more|btnMore/i.test(
          (element.getAttribute("class") || "") + " " +
          (element.getAttribute("id") || ""))));
    const current = new URL(browser.location.href);
    const pageNumber = (url: URL) => Number(url.searchParams.get("page") ||
      url.searchParams.get("p") || url.searchParams.get("page_no") || 1);
    const currentPage = pageNumber(current);
    const forward = Array.from(browser.document.querySelectorAll(
      "[class*='paginate'] a,[class*='paging'] a," +
      "[class*='paginate'] button,[class*='paging'] button," +
      "a[rel='next']")).some((element) => {
      if (!usable(element)) return false;
      const label = text(element);
      const className = element.getAttribute("class") || "";
      if (element.getAttribute("aria-current") === "page" ||
          /(?:^|\s)(?:this|current|active)(?:\s|$)/i.test(className) ||
          /^(?:<+|‹|«|prev(?:ious)?|이전|처음)$/i.test(label) ||
          /(?:^|\s)(?:prev|previous|first)(?:\s|$)/i.test(className)) {
        return false;
      }
      const href = element.getAttribute("href");
      if (href?.startsWith("#") || /^javascript:/i.test(href || "")) {
        return false;
      }
      if (/^\d+$/.test(label) && Number(label) <= currentPage) return false;
      if (!href) return true;
      try {
        const target = new URL(href, current);
        target.hash = "";
        current.hash = "";
        if (target.href === current.href) return false;
        if (target.origin === current.origin &&
            target.pathname === current.pathname &&
            ["page", "p", "page_no"].some((key) =>
              target.searchParams.has(key)) &&
            pageNumber(target) <= currentPage) return false;
        return true;
      } catch {
        // 이동 대상이 불명확한 활성 pagination도 완료로 간주하지 않는다.
        return true;
      }
    });
    if (click && more) more.click();
    return {loadMoreDetected: Boolean(more),
      forwardPaginationDetected: forward, clicked: Boolean(click && more)};
  }, {patternSource:
    "^(?:더\\s*보기|more|load\\s*more|view\\s*more|전체보기|\\+)$",
  click: clickLoadMore});
}
