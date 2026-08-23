#!/usr/bin/env node

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const CHUNK_SIZE = 1024 * 1024;
const CHARSET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
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
	console.log("用法: node .tools/create-random-text-file.js <长度> [输出路径]");
	console.log("");
	console.log("  长度      字符数，或带单位（B / KB / MB / GB，1024 进制）");
	console.log("            字符集: a-z、A-Z、0-9");
	console.log("            例: 512  700B  1KB  1.5MB");
	console.log("  输出路径  省略时在当前目录生成 random_<长度>.txt");
}

function parseSize(input) {
	const text = String(input).trim().replace(/[_\s]/g, "");
	const match = text.match(/^(\d+(?:\.\d+)?)([KMGT]I?B?|B)?$/i);
	if (!match) {
		throw new Error(`无法解析长度: ${input}`);
	}

	const value = Number(match[1]);
	const unit = (match[2] || "B").toUpperCase();
	const multiplier = SIZE_UNITS[unit];
	if (!multiplier) {
		throw new Error(`未知单位: ${match[2]}`);
	}

	const length = Math.round(value * multiplier);
	if (!Number.isSafeInteger(length) || length <= 0) {
		throw new Error(`长度必须为正整数: ${input}`);
	}
	return length;
}

function defaultOutputPath(sizeArg) {
	const safeName = String(sizeArg).trim().replace(/[^\w.-]+/g, "_");
	return path.resolve(`random_${safeName}.txt`);
}

function randomChunk(length) {
	const bytes = crypto.randomBytes(length);
	const chars = Buffer.alloc(length);
	for (let i = 0; i < length; i++) {
		chars[i] = CHARSET.charCodeAt(bytes[i] % CHARSET.length);
	}
	return chars;
}

function writeRandomTextFile(outputPath, length) {
	fs.mkdirSync(path.dirname(outputPath), { recursive: true });

	const fd = fs.openSync(outputPath, "w");
	try {
		let remaining = length;
		while (remaining > 0) {
			const chunkLength = Math.min(CHUNK_SIZE, remaining);
			fs.writeSync(fd, randomChunk(chunkLength));
			remaining -= chunkLength;
		}
		fs.ftruncateSync(fd, length);
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
	const length = parseSize(sizeArg);

	writeRandomTextFile(outputPath, length);
	console.log(`已创建 ${length} 字符的随机字母数字文件: ${outputPath}`);
}

try {
	main(process.argv.slice(2));
} catch (error) {
	console.error(error.message || error);
	process.exit(1);
}
