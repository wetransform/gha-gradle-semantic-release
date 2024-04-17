## [2.0.1](https://github.com/wetransform/gha-gradle-semantic-release/compare/v2.0.0...v2.0.1) (2024-04-17)


### Bug Fixes

* **deps:** update dependency semantic-release to v23.0.8 ([8278f44](https://github.com/wetransform/gha-gradle-semantic-release/commit/8278f44895e16eb6c17c6f571042181ffeb3b510))
* do not run showVersion task for normal publishing ([bbc75c0](https://github.com/wetransform/gha-gradle-semantic-release/commit/bbc75c03c6cf167036ddf111d9b90c027ca01d95))

## [2.0.0](https://github.com/wetransform/gha-gradle-semantic-release/compare/v1.1.0...v2.0.0) (2024-04-17)


### ⚠ BREAKING CHANGES

* requires at least version 2.1.0 of Gradle semantic release version plugin

### Features

* verify that there are no snapshot dependencies before release ([c2f9b26](https://github.com/wetransform/gha-gradle-semantic-release/commit/c2f9b26df571e49f2fa709eb52f6c0bdb7fed8a1))

## [1.1.0](https://github.com/wetransform/gha-gradle-semantic-release/compare/v1.0.1...v1.1.0) (2024-04-12)


### Features

* disable referencing issues without action ([5602c72](https://github.com/wetransform/gha-gradle-semantic-release/commit/5602c723a1daef38d8204812d0831c2974f72d24))
* issues don't require action for reference ([f7ac23f](https://github.com/wetransform/gha-gradle-semantic-release/commit/f7ac23f65f34feade6361e07f9ea9a3965523aef))


### Bug Fixes

* adapt to new version of Gradle plugin ([550246a](https://github.com/wetransform/gha-gradle-semantic-release/commit/550246ae7b9453c1682160db312885353e797a00))
* **deps:** update all non-major dependencies ([8d963bb](https://github.com/wetransform/gha-gradle-semantic-release/commit/8d963bb332d801c2e2501057ea0874a166c6574f))

## [1.0.1](https://github.com/wetransform/gha-gradle-semantic-release/compare/v1.0.0...v1.0.1) (2024-03-31)


### Bug Fixes

* **deps:** update all non-major dependencies ([394b16a](https://github.com/wetransform/gha-gradle-semantic-release/commit/394b16ad7202bf2ed9877e10a493ed5868559ae8))


### Reverts

* ci: release on push ([019c3fd](https://github.com/wetransform/gha-gradle-semantic-release/commit/019c3fdb3d08d747fda13fca7795504ae125b61a))

## 1.0.0 (2024-03-31)


### Features

* do not create release configuration if not required ([9b44e4c](https://github.com/wetransform/gha-gradle-semantic-release/commit/9b44e4c4ae860d8769047929c04ed584163ae33d))
* first action implementation ([166aa0c](https://github.com/wetransform/gha-gradle-semantic-release/commit/166aa0cd352d77faf9d7d7c07fad22db6a8e22b2))
* print version also when not creating a release ([dbf1f56](https://github.com/wetransform/gha-gradle-semantic-release/commit/dbf1f56a843a6a04c3360e13453e1f329f206fdf))


### Bug Fixes

* add missing shell configuration ([0543d76](https://github.com/wetransform/gha-gradle-semantic-release/commit/0543d76e156d867f716505ff66baa92e2c723bc7))
* do not use hard coded branch name ([4c35b73](https://github.com/wetransform/gha-gradle-semantic-release/commit/4c35b73e402303e2af864fe572e0a0bf8456d1e2))
* fix action syntax ([28ab223](https://github.com/wetransform/gha-gradle-semantic-release/commit/28ab223a7be07b49e683b4a4a70bf67c07f8298b))
* fix action syntax ([a5af686](https://github.com/wetransform/gha-gradle-semantic-release/commit/a5af68605ee4df395cad1e419ca7feb7ecb3dc23))
* fix condition for publish step ([15b1ad4](https://github.com/wetransform/gha-gradle-semantic-release/commit/15b1ad478c3a30b1e8e93ac97926c20ccb89704d))
* fix indentation ([4595d8b](https://github.com/wetransform/gha-gradle-semantic-release/commit/4595d8b3239536ab47eca2255eadc06155149593))
* fix setting release version ([cbbee88](https://github.com/wetransform/gha-gradle-semantic-release/commit/cbbee884dd6a7e2a0964acdbb4ee7ed9151a1b4d))
* set RELEASE env variable only for publishing ([d146b8f](https://github.com/wetransform/gha-gradle-semantic-release/commit/d146b8f37cf6f1d27db496c56be8998d8e4d3043))
