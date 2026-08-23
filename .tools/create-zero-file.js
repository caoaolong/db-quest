#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const CHUNK_SIZE = 1024 * 1024;
const SIZE_UNITS = {
	B: 1,
	K: 1024,
	KB: 1024,
	KIB: 1024,
	M: 1024 ** 2,
	MB: 1024 ** 2,
	MIB: 1024 ** 2,
	G: 1024 ** 3,
	GB: 1024 ** 3,
	GIB: 1024 ** 3,
	T: 1024 ** 4,
	TB: 1024 ** 4,
	TIB: 1024 ** 4,
};

function printUsage() {
	console.log("用法: node .tools/create-zero-file.js <大小> [输出路径]");
	console.log("");
	console.log("  大小      字节数，或带单位（B / KB / MB / GB，1024 进制）");
	console.log("            例: 512  700B  1KB  1.5MB");
	console.log("  输出路径  省略时在当前目录生成 zero_<大小>.bin");
}

function parseSize(input) {
	const text = String(input).trim().replace(/[_\s]/g, "");
	const match = text.match(/^(\d+(?:\.\d+)?)([KMGT]I?B?|B)?$/i);
	if (!match) {
		throw new Error(`无法解析大小: ${input}`);
	}

	const value = Number(match[1]);
	const unit = (match[2] || "B").toUpperCase();
	const multiplier = SIZE_UNITS[unit];
	if (!multiplier) {
		throw new Error(`未知单位: ${match[2]}`);
	}

	const bytes = Math.round(value * multiplier);
	if (!Number.isSafeInteger(bytes) || bytes <= 0) {
		throw new Error(`大小必须为正整数字节: ${input}`);
	}
	return bytes;
}

function defaultOutputPath(sizeArg) {
	const safeName = String(sizeArg).trim().replace(/[^\w.-]+/g, "_");
	return path.resolve(`zero_${safeName}.bin`);
}

function writeZeroFile(outputPath, byteCount) {
	fs.mkdirSync(path.dirname(outputPath), { recursive: true });

	const fd = fs.openSync(outputPath, "w");
	try {
		const zeros = Buffer.alloc(Math.min(CHUNK_SIZE, byteCount), 0x00);
		let remaining = byteCount;
		while (remaining > 0) {
			const chunk = Math.min(zeros.length, remaining);
			fs.writeSync(fd, zeros, 0, chunk);
			remaining -= chunk;
		}
		fs.ftruncateSync(fd, byteCount);
	} finally {
		fs.closeSync(fd);
	}
}

function main(argv) {
	if (argv.includes("-h") || argv.includes("--help") || argv.length === 0) {
		printUsage();
		process.exit(argv.length === 0 ? 1 : 0);
	}

	const sizeArg = argv[0];
	const outputPath = path.resolve(argv[1] || defaultOutputPath(sizeArg));
	const byteCount = parseSize(sizeArg);

	writeZeroFile(outputPath, byteCount);
	console.log(`已创建 ${byteCount} 字节的全 0 文件: ${outputPath}`);
}

try {
	main(process.argv.slice(2));
} catch (error) {
	console.error(error.message || error);
	process.exit(1);
}
