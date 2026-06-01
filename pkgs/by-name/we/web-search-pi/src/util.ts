import { DEBUG } from "./constants";

export type Dict = Record<string, unknown>;

export const debug = (...args: readonly unknown[]): void => {
	if (DEBUG) console.error("[web-search]", ...args);
};

export const isDict = (value: unknown): value is Dict => typeof value === "object" && value !== null;
export const str = (value: unknown): string => (typeof value === "string" ? value : "");
export const array = (value: unknown): unknown[] => (Array.isArray(value) ? value : []);
export const unique = <T>(values: readonly T[]): T[] => [...new Set(values)];
export const errorMessage = (error: unknown): string => (error instanceof Error ? error.message : String(error));
