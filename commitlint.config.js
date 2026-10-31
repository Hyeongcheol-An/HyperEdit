module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'subject-case': [0],          // 한국어 제목 허용
    'header-max-length': [2, 'always', 100],
    'body-max-line-length': [0],
  },
};
