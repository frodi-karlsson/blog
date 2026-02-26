import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

test.describe("Accessibility", () => {
  test("home page should not have automatically detectable accessibility issues", async ({
    page,
  }) => {
    await page.goto("/");
    const accessibilityScanResults = await new AxeBuilder({ page }).analyze();
    expect(accessibilityScanResults.violations).toEqual([]);
  });

  test("blog post should not have automatically detectable accessibility issues", async ({
    page,
  }) => {
    await page.goto("/bespoke-elixir-web-framework");
    const accessibilityScanResults = await new AxeBuilder({ page }).analyze();
    expect(accessibilityScanResults.violations).toEqual([]);
  });
});

test("should load the home page", async ({ page }) => {
  await page.goto("/");
  await expect(page).toHaveTitle(/Fróði Karlsson/);
  await expect(page.getByTestId("blog-index-header")).toBeVisible();
});

test("should navigate to a blog post", async ({ page }) => {
  await page.goto("/");
  const postLink = page.getByTestId("blog-post-link").first();
  const postTitle = await postLink.innerText();

  await postLink.click();

  await expect(page.getByTestId("blog-post-header").locator("h1")).toHaveText(postTitle);
  await expect(page.getByTestId("blog-post-content")).toBeVisible();
});
