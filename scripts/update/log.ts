import { type AnnotationKind, gha } from "../github-actions/github-actions";

let failureAnnotationKind: AnnotationKind = "error";
export function logError(message: string, file?: string): void {
	gha(failureAnnotationKind, message, file);
}
export function logInfo(message: string): void {
	gha("debug", message);
}
export function logNotice(message: string, file?: string): void {
	gha("notice", message, file);
}

export function toleratedFailureAnnotations<T>(action: () => T): T {
	const previous = failureAnnotationKind;
	failureAnnotationKind = "warning";
	try {
		return action();
	} finally {
		failureAnnotationKind = previous;
	}
}
