// Invoked in WebKit's client content world on the configured BI Data origin.
if (operation === "cancelExport") {
    (globalThis.plaExportController ??= new AbortController()).abort();
    return true;
}
const exportController = ["productParameters", "downloadProduct", "submitSales", "checkDownload"].includes(operation)
    ? (globalThis.plaExportController ??= new AbortController()) : null;
const visible = element => !!element?.getClientRects().length &&
    element.ownerDocument.defaultView.getComputedStyle(element).visibility !== "hidden";
const text = element => (element?.innerText || element?.value || "").trim().replace(/\s+/g, " ");
const matching = (root, selector, predicate) =>
    Array.from(root.querySelectorAll(selector)).filter(e => visible(e) && predicate(e));
const find = (root, selector, predicate) => {
    const matches = matching(root, selector, predicate);
    return matches.length === 1 ? matches[0] : null;
};
const button = (root, pattern) => find(root, "button,[role=button],input[type=button]", e => pattern.test(text(e)));
const nameOf = input => input.getAttribute("aria-label") ||
    Array.from(input.labels || [], label => text(label)).join(" ") || text(input.parentElement);
const checkbox = (root, label) => find(root, "input[type=checkbox]", e => nameOf(e) === label);
const frameDocument = frame => {
    try { return frame?.contentDocument; } catch { return null; }
};
const visibleFrames = Array.from(document.querySelectorAll("iframe")).filter(visible);
const reportPath = "/ChannelReleaseEffect";
const isReportPath = path => path.replace(/\/$/, "") === reportPath;
const reportDocuments = isReportPath(location.pathname) ? [document] :
    visibleFrames.filter(frame => frame.src && isReportPath(new URL(frame.src).pathname))
        .map(frameDocument).filter(Boolean);
const report = reportDocuments.find(doc => button(doc, /查询$/));
const query = report && button(report, /查询$/);
const navigationControls = "a,button,[role=button],[role=menuitem],[role=tab]";
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const wait = async (read, label) => {
    for (let attempt = 0; attempt < 25; attempt++) {
        const value = read();
        if (value) return value;
        await delay(120);
    }
    throw new Error("BI Data 控件未就绪：" + label);
};
const needed = (element, label) => {
    if (!element) throw new Error("无法确认报表控件：" + label);
    return element;
};
const checked = (input, value) => {
    if (input.checked !== value) input.click();
    if (input.checked !== value) throw new Error("BI Data 未应用筛选");
};

if (operation === "authenticated") {
    if (query) return true;
    if (Array.from(document.querySelectorAll('input[type="password"]')).some(visible)) return false;
    const hasSignOut = matching(document, navigationControls,
        e => /^(退出(?:登录)?|log\s*out|sign\s*out)$/i.test(text(e))).length > 0;
    const portalShell = /(?:^|\n)\s*(快捷导航|Quick Navigation|Welcome)\s*(?:\n|$)/i;
    return hasSignOut && portalShell.test(document.body?.innerText || "");
}
if (operation === "ready") {
    if (query) return true;
    if (args.open) {
        // Favorites and recent visits are inside the same-origin Welcome frame.
        const navigationDocuments = [document, ...visibleFrames.map(frameDocument).filter(Boolean)];
        const entry = navigationDocuments.flatMap(doc =>
            matching(doc, navigationControls, e => text(e) === "渠道投放分析"))[0];
        if (entry) {
            entry.click();
            return "opening";
        }
    }
    return false;
}
const metadata = async (path, parameters = {}, method = "GET") => {
    const url = new URL(path, location.origin);
    const fields = new URLSearchParams(parameters);
    const request = {method, credentials: "same-origin", signal: exportController?.signal};
    if (method === "GET") url.search = fields.toString();
    else request.body = fields;
    const response = await fetch(url, request);
    if (!response.ok || response.redirected) throw new Error("BI Data 筛选接口请求失败：" + path);
    return response.json();
};
const categoryChoices = async merchantId => {
    const response = await metadata("/fe/common/getCategoryList", {
        ignorePrivilege: false, maxLevel: 3, merchantId
    });
    const items = Array.isArray(response) ? response : response.data;
    if (!Array.isArray(items)) throw new Error("BI Data 品类数据格式无效");
    const byID = new Map(items.map(item => [String(item.categories_id), item]));
    return [...byID.values()].flatMap(item => {
        const path = [item];
        while (path.length < 3) {
            const parent = byID.get(String(path[0].parent_categories_id));
            if (!parent || path.includes(parent)) break;
            path.unshift(parent);
        }
        // The report renders the cascade from level 1 and requires a complete path.
        if (!path.every((node, index) => Number(node.categories_level) === index + 1 &&
            Number(node.categories_id) > 0 && node.categories_name)) return [];
        return [{path, label: path.map(node => node.categories_name).join(" / ")}];
    });
};
const leaf = choice => choice.path[choice.path.length - 1];
const usesCategories = filters => filters.classification === "category" ||
    (!filters.classification && (!!filters.category || !!filters.selectedCategories?.length));
const selectedCategoryPaths = (choices, filters) => {
    if (filters.selectedCategories?.length) {
        const byID = new Map(choices.map(choice => [String(leaf(choice).categories_id), choice]));
        const ids = [...new Set(filters.selectedCategories.map(category => category.id))];
        const matches = ids.map(id => byID.get(id));
        if (matches.some(match => !match)) throw new Error("所选品类已不可用，请重新选择");
        if (new Set(matches.map(match => Number(leaf(match).categories_level))).size !== 1) {
            throw new Error("只能同时选择同一层级的品类");
        }
        return matches;
    }
    if (!filters.category) return [];
    const exact = choices.filter(choice => choice.label === filters.category);
    const matches = exact.length ? exact : choices.filter(choice => leaf(choice).categories_name === filters.category);
    if (matches.length !== 1) throw new Error("无法唯一确认品类，请重新选择完整的品类路径");
    return matches;
};
const names = (items, key) => [...new Set(items.map(item => item[key]).filter(name => typeof name === "string" && name))];
const weekLabel = optionName => optionName.trim().split(/\s+/)[0];

const productReportBase = "/fe/MarketPerformance/PLAMarketCostPerformance";
const productWeekRange = (dates, firstWeek, lastWeek) => {
    const byWeek = new Map();
    for (const day of dates) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(day.dt)) continue;
        const key = `${day.year}-W${String(day.week).padStart(2, "0")}`;
        const days = byWeek.get(key) ?? [];
        days.push(day.dt);
        byWeek.set(key, days);
    }
    const weeks = [...byWeek].map(([key, days]) => {
        const sorted = [...new Set(days)].sort();
        return {key, start: sorted[0], end: sorted[sorted.length - 1], count: sorted.length};
    }).sort((a, b) => a.start.localeCompare(b.start));
    const first = weeks.findIndex(week => week.key === firstWeek);
    const last = weeks.findIndex(week => week.key === lastWeek);
    const previous = first - (last - first + 1);
    if (first < 0 || last < first || previous < 0 ||
        weeks.slice(previous, last + 1).some(week => week.count !== 7)) {
        throw new Error("BI Data 无法确认所选报表周及对比周");
    }
    return {
        startDate: weeks[first].start, endDate: weeks[last].end,
        comparedStarDate: weeks[previous].start, comparedEndDate: weeks[first - 1].end
    };
};

if (operation === "productParameters") {
    const f = args.filters;
    const [merchants, dates, units, countries, tags] = await Promise.all([
        metadata("/fe/common/getMerchantList"),
        metadata("/fe/common/getLitbWeekList"),
        metadata("/fe/common/getBUList"),
        f.country ? metadata(productReportBase + "/getCountryList") : [],
        metadata("/common/getProductTags")
    ]);
    const merchant = needed(merchants.find(item => item.merchant_name === (f.merchant || "LITB")), "商户");
    const isCategory = usesCategories(f);
    const unit = isCategory ? "" : f.businessUnit;
    if (unit && !units.some(item => item.bu === unit)) throw new Error("投放产品明细没有所选 BU");
    const choices = (unit || (isCategory && (f.category || f.selectedCategories?.length)))
        ? await categoryChoices(merchant.merchant_id) : [];
    const selected = isCategory ? selectedCategoryPaths(choices, f) : [];
    if (selected.length > 1) throw new Error("投放产品明细只支持单个品类");
    const categoryNode = isCategory
        ? selected.map(leaf)[0]
        : choices.find(choice => choice.path.length === 1 && choice.label === unit)?.path[0];
    const countryKey = f.country.trim().toUpperCase();
    let country = countries.find(item =>
        item.country_name.trim().toUpperCase() === countryKey || item.country_code.toUpperCase() === countryKey);
    if (f.country && !country) {
        const sets = await metadata("/Country/getCountrySet", {ignorePrivilege: false});
        if (sets.length) {
            const list = await metadata("/Country/getCountryOfCountrySet", {countrySet: sets.map(item => item.VALUE).join(",")});
            const code = list.find(item => item.NAME.trim().toUpperCase() === countryKey)?.VALUE;
            country = countries.find(item => item.country_code === code);
        }
        if (!country) throw new Error("投放产品明细没有所选国家");
    }
    const dimensions = {"日期": "period", "国家": "country", "二级品类": "cms2", "三级品类": "cms3"};
    const range = productWeekRange(dates, f.firstWeek, f.lastWeek);
    const daily = !!f.productDetailThroughDay;
    if (daily) {
        range.endDate = range.endDate < f.productDetailThroughDay ? range.endDate : f.productDetailThroughDay;
        if (range.endDate < range.startDate) throw new Error("投放产品明细的起始周晚于今天");
        const start = Date.parse(range.startDate);
        const end = Date.parse(range.endDate);
        const day = 86400000;
        range.comparedEndDate = new Date(start - day).toISOString().slice(0, 10);
        range.comparedStarDate = new Date(start - (end - start + day)).toISOString().slice(0, 10);
    }
    return {
        dateType: daily ? "BY_DAY" : "BY_WEEK", ...range,
        merchantId: Number(merchant.merchant_id), categoryId: Number(categoryNode?.categories_id ?? 0),
        categoryLevel: Number(categoryNode?.categories_level ?? 0),
        bu: unit ? [unit] : names(units, "bu"), country: country ? [country.country_code] : [],
        productType: tags.productTagsList.map(item => Number(item.VALUE)),
        lsin: [], productStateMC: [], label: [], advantage: [], product_line: [], product_line_men: [], productTag: [],
        sort_field: "cost", sort_order: "desc",
        exportDatatype: daily ? ["period", "lsin", "cms1", "cms2", "cms3", "cms4"] :
            Object.keys(dimensions).filter(key => f.dimensions.includes(key)).map(key => dimensions[key])
    };
}

if (operation === "downloadProduct") {
    const controller = exportController;
    const timeout = setTimeout(() => controller.abort(), 300000);
    try {
        const response = await fetch(productReportBase + "/exportProductData", {
            method: "POST", credentials: "same-origin", headers: {"Content-Type": "application/json"},
            body: JSON.stringify(args.parameters), signal: controller.signal
        });
        if (!response.ok || response.redirected) return false;
        const file = await response.blob();
        const signature = new Uint8Array(await file.slice(0, 4).arrayBuffer());
        if (controller.signal.aborted) return false;
        if (signature.join(",") !== "80,75,3,4") return false;
        const link = document.createElement("a");
        link.href = URL.createObjectURL(file);
        link.download = "投放产品明细.xlsx";
        document.body.append(link);
        link.click();
        link.remove();
        return true;
    } finally {
        clearTimeout(timeout);
    }
}

if (operation === "submitSales") {
    const filters = args.filters;
    const [merchants, dates, units, channels, buGroups] = await Promise.all([
        metadata("/fe/common/getMerchantList"),
        metadata("/fe/common/getLitbWeekList"),
        metadata("/SubNationalProfit/BulistByUser"),
        metadata("/common/getChannelByField", {ignorePrivilege: false, field: "channel_set"}),
        metadata("/fe/common/getBuGroupPermission", {ignorePrivilege: false}, "POST")
    ]);
    const merchant = needed(merchants.find(item => item.merchant_name === filters.merchant), "商户");
    const selected = selectedCategoryPaths(await categoryChoices(merchant.merchant_id), filters);
    if (selected.length !== 1) throw new Error("Product Sales 每次导出需要一个明确的品类");
    const category = leaf(selected[0]);
    const categoryLevel = Number(category.categories_level);
    const categoryId = String(category.categories_id);
    const categoryInfo = (id, level) => metadata("/common/categoryInfo", {
        id, level, merchant_id: merchant.merchant_id
    });
    const parentId = selected[0].path[categoryLevel - 2]?.categories_id ?? 0;
    const [siblings, children] = await Promise.all([
        categoryInfo(parentId, categoryLevel - 1), categoryInfo(categoryId, categoryLevel)
    ]);
    const visibleCategory = needed(siblings.flatMap(item => item.children ?? [item])
        .find(item => String(item.id) === categoryId), "Product Sales 品类权限");
    if (children.length && Number(visibleCategory.categoryFlag) !== 1) {
        throw new Error("当前 BI Data 账号无法导出此品类，请选择有权限的下级品类");
    }
    // The legacy report expects the selected node followed by its immediate children.
    const legacyCategoryId = [categoryId, ...children.map(item => item.id)].join("_");
    const channel = needed(channels.channelGroupList.find(item => item.NAME === filters.channel), "渠道");
    const range = productWeekRange(dates, filters.firstWeek, filters.lastWeek);
    const endDate = range.endDate < filters.productDetailThroughDay ? range.endDate : filters.productDetailThroughDay;
    if (!endDate || endDate < range.startDate) throw new Error("Product Sales 的起始周晚于今天");
    const bus = names(units, "BU").join(",");
    if (!bus) throw new Error("无法确认 Product Sales 可用的 BU");
    const params = {
        merchantId: String(merchant.merchant_id),
        categoryLevel, categoryId: legacyCategoryId,
        sDate: range.startDate, eDate: endDate, timeFlag: "day",
        openType: "tps.STAT_DATE,tps.LSIN", channelSet: [channel.NAME],
        application: "total", sortField: "orders", bus, lsins: "", countryCode: "all",
        m_start: "", m_end: "", productTags: [], cateType: "0", combination: "false",
        expandCountry: "false", exportTagSel: "", exportTagValueSel: [], styleNum: "", supplier: "",
        productState: "all", tagName: [],
        buGroup: buGroups.length === 0 ? ["-99"] :
            buGroups.length === Number(buGroups[0].BTS) ? [] : names(buGroups, "BU_GROUP"),
        report_name: "product_sales_detail", user_defined: args.task,
        exportVisibleFields: "", exportContent: ["lsin", "sales", "basic1", "flow1"], exportTagSelGroup: ""
    };
    const controller = exportController;
    const timeout = setTimeout(() => controller.abort(), 30000);
    try {
        const response = await fetch("/ProductSales/AppProductSales/export", {
            method: "POST", credentials: "same-origin", headers: {"Content-Type": "application/json"},
            body: JSON.stringify(params), signal: controller.signal
        });
        if (!response.ok || response.redirected) throw new Error("Product Sales 导出接口请求失败");
        const id = await response.json();
        return Number.isSafeInteger(Number(id)) ? Number(id) : 0;
    } finally {
        clearTimeout(timeout);
    }
}

if (operation !== "checkDownload") needed(query, "查询");

if (operation === "options") {
    const [channels, businessUnits, countrySets, weeks, merchants] = await Promise.all([
        metadata("/common/getChannelGroup", {ignorePrivilege: false}, "POST"),
        metadata("/SubNationalProfit/BulistByUser"),
        metadata("/Country/getCountrySet", {ignorePrivilege: false}),
        metadata("/fe/common/getWeekList"),
        metadata("/common/categorygroup")
    ]);
    const merchant = needed(args.merchant ? merchants.find(item => item.name === args.merchant) : merchants[0], "商户");
    const [countries, categories] = await Promise.all([
        countrySets.length ? metadata("/Country/getCountryOfCountrySet", {
            countrySet: countrySets.map(item => item.VALUE).join(",")
        }) : [],
        categoryChoices(merchant.value)
    ]);
    return {
        channels: names(channels.channelGroupList, "NAME"),
        businessUnits: names(businessUnits, "BU"),
        countries: names(countries, "NAME"),
        categoryTree: categories.map(choice => ({
            id: String(leaf(choice).categories_id),
            parentID: choice.path.length > 1 ? String(leaf(choice).parent_categories_id) : null,
            level: Number(leaf(choice).categories_level),
            name: leaf(choice).categories_name,
            path: choice.label
        })),
        reportWeeks: [...new Set(names(weeks.data_list, "NAME").map(weekLabel))],
        merchants: names(merchants, "name")
    };
}

const populatedSelect = (id, label) => wait(() => {
    const select = report.getElementById(id);
    return select?.options.length ? select : null;
}, label);

const selectNamedOption = async (id, name, label) => {
    const select = await populatedSelect(id, label);
    const matches = Array.from(select.options).filter(option => option.text.trim() === name);
    if (matches.length !== 1) throw new Error("BI Data 无法确认筛选项：" + label);
    select.value = matches[0].value;
    return select.value;
};

const applyChannelGroup = async name => {
    const select = await populatedSelect("channelInstall", "渠道");
    if (!name) return;
    const groupID = await selectNamedOption("channelGroup", name, "渠道分组");
    const channels = await metadata("/ChannelReleaseEffect/getChannelDetail", {channelGroupIds: groupID});
    const ids = new Set(channels.map(channel => String(channel.CHANNEL_ID)));
    for (const option of select.options) option.selected = ids.has(option.value);
    if (ids.size === 0 || select.selectedOptions.length !== ids.size) {
        throw new Error("BI Data 未能应用所选渠道分组");
    }
};

const applyMerchant = async (isCategory, name) => {
    const select = await populatedSelect(isCategory ? "merchantSingle" : "merchant", "商户");
    if (name) {
        const option = Array.from(select.options).find(item => item.text.trim().replace(/^商户\s*[:：]\s*/, "") === name);
        const value = needed(option, "商户").value;
        if (select.value !== value || select.selectedOptions.length !== 1) {
            if (isCategory) {
                const trigger = select.parentElement.querySelector("button.multiselect");
                needed(trigger, "商户").click();
                const input = await wait(() => find(trigger.parentElement, "input", e => e.value === value), "商户选项");
                input.click();
            } else {
                select.value = value;
                select.dispatchEvent(new Event("change", {bubbles: true}));
            }
        }
        if (select.value !== value) throw new Error("BI Data 未应用所选商户");
    }
    return needed(select.value, "商户");
};

const applyCategories = async (merchantId, filters) => {
    if (!filters.category && !filters.selectedCategories?.length) return;
    const matches = selectedCategoryPaths(await categoryChoices(merchantId), filters);
    const input = await wait(() => {
        const field = report.getElementById("inputBox");
        return visible(field) && (text(field).includes("点击选择品类") || field.querySelector(".tag-badge")) ? field : null;
    }, "品类面板");
    input.click();
    if (report.getElementById("allCheck")?.checked) {
        needed(report.getElementById("allItem"), "全部品类").click();
    }
    for (const {path} of matches) {
        for (const [index, node] of path.entries()) {
            const item = await wait(() => Array.from(report.querySelectorAll(".cascader-item[data-id]"))
                .find(element => element.dataset.id === String(node.categories_id) && visible(element)), "品类层级");
            if (index + 1 === path.length) {
                const checkbox = needed(item.querySelector("input[type=checkbox]"), "品类复选框");
                if (checkbox.disabled) throw new Error("BI Data 禁用了所选品类：" + node.categories_name);
                if (!checkbox.checked) item.click();
                if (!checkbox.checked) throw new Error("BI Data 未应用所选品类：" + node.categories_name);
            } else {
                item.dispatchEvent(new report.defaultView.MouseEvent("mouseover", {bubbles: true}));
            }
        }
    }
    input.click();
};

const exportPrompt = () => find(report, ".layui-layer", e =>
    text(e.querySelector(".layui-layer-title")) === "请设置导出任务名称");
const exportNameField = prompt => find(prompt, "textarea,input[type=text]", () => true);
const confirmExportButton = prompt => find(prompt, "a,button", e => text(e) === "确定");

if (operation === "prepare") {
    const f = args.filters;
    const isCategory = usesCategories(f);
    const mode = report.querySelector(`input[name="dataType2"][value="${isCategory ? "category" : "bu"}"]`);
    checked(needed(mode, "分类方式"), true);
    const merchant = await applyMerchant(isCategory, f.merchant);
    const dimensions = needed(report.getElementById("dataType"), "展开维度");
    const dimensionChoices = Array.from(dimensions.options);
    for (const label of f.dimensions) {
        if (!dimensionChoices.some(option => option.text.trim() === label)) {
            throw new Error("BI Data 找不到展开维度：" + label);
        }
    }
    for (const option of dimensionChoices) option.selected = f.dimensions.includes(option.text.trim());
    dimensions.dispatchEvent(new Event("change", {bubbles: true}));
    needed(button(report, /时间粒度/), "时间粒度").click();
    checked(await wait(() => checkbox(report, "周"), "周粒度"), true);
    for (const [selector, label] of [["#week_start", f.firstWeek], ["#week_end", f.lastWeek]]) {
        const {select, option} = await wait(() => {
            const select = report.querySelector(selector);
            if (!select) return null;
            const matches = Array.from(select.options).filter(item => weekLabel(item.text) === label);
            return matches.length === 1 ? {select, option: matches[0]} : null;
        }, "报表周 " + label);
        select.value = option.value;
        select.dispatchEvent(new Event("change", {bubbles: true}));
    }
    await applyChannelGroup(f.channel);
    if (f.country) await selectNamedOption("country", f.country, "国家");
    if (isCategory) {
        await applyCategories(merchant, f);
    } else if (f.businessUnit) {
        await selectNamedOption("buList", f.businessUnit, "BU");
    }
    // BI Data's export action reads the current filters itself.
    const exportButton = needed(report.getElementById("daochu"), "导出");
    exportButton.click();
    const prompt = await wait(exportPrompt, "导出确认窗口");
    const input = needed(exportNameField(prompt), "任务名称");
    input.value = args.task;
    input.dispatchEvent(new Event("input", {bubbles: true}));
    needed(confirmExportButton(prompt), "确定");
    return true;
}

if (operation === "confirm") {
    const prompt = needed(exportPrompt(), "导出任务");
    const input = needed(exportNameField(prompt), "任务名称");
    if (input.value !== args.task) throw new Error("无法确认本次任务名称");
    needed(confirmExportButton(prompt), "确定").click();
    return true;
}

if (operation === "checkDownload") {
    const url = new URL("/common2/look", location.origin);
    url.search = new URLSearchParams({export_id: args.exportID ?? "", exportname: args.exportName ?? "渠道投放分析"});
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);
    const cancel = () => controller.abort();
    if (exportController.signal.aborted) cancel();
    exportController.signal.addEventListener("abort", cancel, {once: true});
    let rows;
    try {
        const response = await fetch(url, {credentials: "same-origin", cache: "no-store", signal: controller.signal});
        if (!response.ok || response.redirected) return {status: "unavailable"};
        rows = await response.json();
    } catch {
        return {status: "unavailable"};
    } finally {
        clearTimeout(timeout);
        exportController.signal.removeEventListener("abort", cancel);
    }
    if (!Array.isArray(rows)) return {status: "unavailable"};
    const matchingRows = rows.filter(row => row.USER_DEFINED === args.task);
    if (!matchingRows.length) return {status: "missing"};
    if (matchingRows.length !== 1) return {status: "ambiguous"};
    const row = matchingRows[0];
    const state = Number(row.STATE);
    if (state === 1 || state === 3) return {status: "pending"};
    if (state !== 2) return {status: "failed"};
    if (typeof row.PATH !== "string" || !row.PATH.trim()) return {status: "unavailable"};
    const download = new URL("/common2/DownFile", location.origin);
    download.searchParams.set("path", row.PATH);
    return {status: "ready", url: download.href};
}
throw new Error("Unknown BI Data operation");
