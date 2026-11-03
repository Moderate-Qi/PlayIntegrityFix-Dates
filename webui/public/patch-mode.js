/* Local date-mode control. Uses the same KernelSU WebUI exec bridge as PIF. */
(() => {
  const HELPER = "/data/adb/modules/playintegrityfix/patch_mode.sh";
  let requestId = 0;

  function exec(command) {
    return new Promise((resolve, reject) => {
      if (typeof ksu === "undefined") {
        reject(new Error("请在 KernelSU 模块 WebUI 中使用此功能。"));
        return;
      }
      const callback = `pifPatchMode_${Date.now()}_${requestId++}`;
      window[callback] = (code, stdout, stderr) => {
        delete window[callback];
        if (Number(code) !== 0) reject(new Error((stderr || stdout || "命令执行失败").trim()));
        else resolve(stdout || "");
      };
      try { ksu.exec(command, "{}", callback); }
      catch (error) { delete window[callback]; reject(error); }
    });
  }

  function parseStatus(text) {
    const result = {};
    for (const line of text.trim().split("\n")) {
      const split = line.indexOf("=");
      if (split >= 0) result[line.slice(0, split)] = line.slice(split + 1).trim();
    }
    if (!["official", "day01", "split", "custom"].includes(result.mode)) {
      throw new Error("无法读取日期模式，请确认新模块已刷入并重启。" );
    }
    return result;
  }

  function dateFromFields(year, month, day) {
    if (!/^\d{4}$/.test(year) || !/^\d{1,2}$/.test(month) || !/^\d{1,2}$/.test(day)) return null;
    const y = Number(year), m = Number(month), d = Number(day);
    const leap = y % 400 === 0 || (y % 4 === 0 && y % 100 !== 0);
    const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (y < 1 || m < 1 || m > 12 || d < 1 || d > days[m - 1]) return null;
    return `${year}-${month.padStart(2, "0")}-${day.padStart(2, "0")}`;
  }

  class PatchMode extends HTMLElement {
    constructor() {
      super();
      this.state = null;
      this.saving = false;
      this.running = false;
      this.onFocus = () => { if (!this.running && !this.saving) this.refresh(); };
    }

    get disabled() { return this.running; }
    set disabled(value) {
      const wasRunning = this.running;
      this.running = Boolean(value);
      this.updateDisabled();
      if (wasRunning && !this.running && this.isConnected) this.refresh();
    }

    connectedCallback() {
      if (this.initialized) return;
      this.initialized = true;
      this.innerHTML = `
        <section class="patch-mode-card" aria-label="Autopif 补丁日期模式">
          <div class="patch-mode-heading">
            <strong>补丁日期 · dates1.2</strong>
            <div class="patch-mode-actions">
              <button class="patch-mode-button" data-refresh type="button">刷新</button>
              <button class="patch-mode-button" data-edit type="button" hidden>改日期</button>
            </div>
          </div>
          <label>
            <select aria-label="安全补丁日期模式" disabled>
              <option value="split">Google 原值 / 系统原值</option>
              <option value="official">官方原始日期模式</option>
              <option value="day01">day01 模式</option>
              <option value="custom">自定义安全补丁日期</option>
            </select>
          </label>
          <details class="patch-mode-details">
            <summary>
              <span class="patch-mode-current" data-current>读取中…</span>
              <span class="patch-mode-detail-label">详情</span>
            </summary>
            <p class="patch-mode-info" data-next>正在读取已保存的模式…</p>
            <p class="patch-mode-info" data-system></p>
          </details>
          <p class="patch-mode-feedback" data-feedback role="status" aria-live="polite"></p>
        </section>
        <dialog class="patch-mode-dialog" aria-label="自定义安全补丁日期">
          <form novalidate>
            <h2>自定义安全补丁日期</h2>
            <p>输入年、月、日。保存后，下次点击 Autopif 使用这个日期。</p>
            <div class="patch-mode-date-fields">
              <label><span>年</span><input aria-label="年" name="year" inputmode="numeric" type="text" maxlength="4" placeholder="2026" autocomplete="off"></label>
              <label><span>月</span><input aria-label="月" name="month" inputmode="numeric" type="text" maxlength="2" placeholder="11" autocomplete="off"></label>
              <label><span>日</span><input aria-label="日" name="day" inputmode="numeric" type="text" maxlength="2" placeholder="01" autocomplete="off"></label>
            </div>
            <p class="patch-mode-feedback error" data-error role="alert"></p>
            <div class="patch-mode-actions">
              <button class="patch-mode-button" data-cancel type="button">取消</button>
              <button class="patch-mode-button primary" type="submit">保存日期</button>
            </div>
          </form>
        </dialog>`;
      this.select = this.querySelector("select");
      this.dialog = this.querySelector("dialog");
      this.form = this.querySelector("form");
      this.select.addEventListener("change", () => {
        if (this.select.value === "custom") this.openCustom();
        else this.save(this.select.value);
      });
      this.querySelector("[data-edit]").addEventListener("click", () => this.openCustom());
      this.querySelector("[data-refresh]").addEventListener("click", () => this.refresh());
      this.querySelector("[data-cancel]").addEventListener("click", () => this.cancelCustom());
      this.dialog.addEventListener("cancel", event => {
        event.preventDefault();
        if (!this.saving) this.cancelCustom();
      });
      this.dialog.addEventListener("close", () => {
        if (this.state) this.select.value = this.state.mode;
      });
      this.form.addEventListener("submit", event => {
        event.preventDefault();
        const fields = this.form.elements;
        const date = dateFromFields(fields.year.value.trim(), fields.month.value.trim(), fields.day.value.trim());
        if (!date) {
          this.querySelector("[data-error]").textContent = "请输入真实存在的日期：四位年份、1–12 月及该月有效日号。";
          return;
        }
        this.save("custom", date);
      });
      window.addEventListener("focus", this.onFocus);
      this.refresh();
    }

    disconnectedCallback() { window.removeEventListener("focus", this.onFocus); }

    updateDisabled() {
      if (!this.select) return;
      this.select.disabled = this.running || this.saving || !this.state;
      this.querySelector("[data-edit]").disabled = this.running || this.saving;
      this.querySelector("[data-refresh]").disabled = this.running || this.saving;
      this.form.querySelectorAll("button, input").forEach(control => { control.disabled = this.saving; });
    }

    feedback(text, error = false) {
      const field = this.querySelector("[data-feedback]");
      field.textContent = text;
      field.classList.toggle("error", error);
    }

    async refresh() {
      if (this.reading) return this.reading;
      this.reading = (async () => {
        try {
          this.state = parseStatus(await exec(`sh ${HELPER} status`));
          this.render();
          return true;
        } catch (error) {
          this.feedback(error.message, true);
          return false;
        } finally { this.updateDisabled(); }
      })();
      try { return await this.reading; }
      finally { this.reading = null; }
    }

    render() {
      const s = this.state;
      if (!this.dialog.open) this.select.value = s.mode;
      const shortDate = value => /^\d{4}-\d{2}-\d{2}$/.test(value || "") ? value.slice(5) : "待同步";
      this.querySelector("[data-current]").textContent = `PIF ${shortDate(s.current_date)} · 系统 ${shortDate(s.build_date)}`;
      const modes = {
        split: "下次 Autopif：Google 使用指纹原始日期；系统与 Vendor 各自恢复镜像原始补丁日期，普通应用的硬件证明同步跟随系统。需要当前 TSOSS 199，保存时开启补丁同步。",
        official: "下次 Autopif：采用服务器原始日期（通常以 05 结尾）。",
        day01: "下次 Autopif：保留服务器年月，将末尾 05 改为 01。",
        custom: `下次 Autopif：使用自定义日期 ${s.custom_date}。`
      };
      this.querySelector("[data-next]").textContent = modes[s.mode];
      this.querySelector("[data-system]").textContent =
        `PIF：${s.current_date || "未读取到"} · 系统：${s.build_date || "未读取到"} · Vendor：${s.vendor_date || "未读取到"}` +
        ` · TS 默认：${s.ts_default_boot || "待同步"} · TS Google：${s.ts_google_boot || "跟随默认"}` +
        (s.sync_enabled === "true" ? " · 补丁同步已开启" : " · 请开启原有「同步安全补丁」以同步系统和 Tricky Store");
      this.querySelector("[data-edit]").hidden = s.mode !== "custom";
    }

    openCustom() {
      const s = this.state;
      const now = new Date();
      const fallback = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-01`;
      const parts = (s.custom_date || s.current_date || fallback).split("-");
      const fields = this.form.elements;
      [fields.year.value, fields.month.value, fields.day.value] = parts;
      this.querySelector("[data-error]").textContent = "";
      this.dialog.showModal();
    }

    cancelCustom() {
      if (this.state) this.select.value = this.state.mode;
      this.dialog.close();
    }

    async save(mode, date = "") {
      this.saving = true;
      this.feedback("正在保存…");
      this.updateDisabled();
      try {
        // mode is from fixed options; date has passed numeric calendar validation.
        await exec(`sh ${HELPER} set ${mode}${date ? " " + date : ""}`);
        if (this.dialog.open) this.dialog.close();
        const refreshed = await this.refresh();
        if (refreshed) this.feedback("已保存，运行 Autopif 后重启。");
      } catch (error) {
        if (this.state) this.select.value = this.state.mode;
        this.feedback(error.message, true);
        if (this.dialog.open) this.querySelector("[data-error]").textContent = error.message;
      } finally {
        this.saving = false;
        this.updateDisabled();
      }
    }
  }

  customElements.define("pif-patch-mode", PatchMode);
})();
