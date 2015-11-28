<?php
/**
 * ICache interface file.
 *
 * PHP version 5.4
 *
 * @category IveeCrest
 * @package  IveeCrestInterfaces
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/ICache.php
 */

namespace iveeCrest;

/**
 * Interface for caches
 *
 * @category IveeCrest
 * @package  IveeCrestInterfaces
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/ICache.php
 */
interface ICache
{
    /**
     * Stores item in cache.
     *
     * @param \iveeCrest\ICacheable $item to be stored
     *
     * @return bool true on success
     */
    public function setItem(ICacheable $item);

    /**
     * Gets item from cache.
     *
     * @param string $key under which the item is stored
     *
     * @return \iveeCrest\ICacheable
     * @throws \iveeCrest\Exceptions\KeyNotFoundInCacheException if key is not found
     */
    public function getItem($key);

    /**
     * Removes item from cache.
     *
     * @param string $key of object to be removed
     *
     * @return bool true on success or if cache use has been disabled
     */
    public function deleteItem($key);

    /**
     * Removes multiple items from cache.
     *
     * @param array $keys of items to be removed
     *
     * @return bool true on success, also if cache use has been disabled
     */
    public function deleteMulti(array $keys);

    /**
     * Clears all stored items in cache or all iveeCrest-related items.
     *
     * @return boolean true on success, also if cache use has been disabled.
     */
    public function flushCache();

    /**
     * Gets the number of hits the cache wrapper registered.
     *
     * @return int the number of hits
     */
    public function getHits();
}
