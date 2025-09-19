
// also edit class name in style.css when changing this.
const resizableImageClass = "resizable";

const EditorDefaultHtml = "<p>​</p>";


var editor = {

    _textField: document.getElementById('editor'),

    _htmlSetByApplication: null,

    _currentSelection: {
        "startContainer": 0,
        "startOffset": 0,
        "endContainer": 0,
        "endOffset": 0
    },

    _useWindowLocationForEditorStateChangedCallback: false,

    _imageMinWidth: 100,
    _imageMinHeight: 50,

    _isImageResizingEnabled: true,

    _lastKnownHeight: 0,
    _heightNotifyScheduled: false,
    _forceHeightNotification: false,

    init: function() {
        document.addEventListener("selectionchange", function() {
            editor._backupRange();
            editor._handleTextEntered(); // in newly selected area different commands may be activated / deactivated
        });

        this._textField.addEventListener("keydown", function(e) {
            var BACKSPACE = 8;
            var M = 77;

            if(e.which == BACKSPACE) {
                if(editor._textField.innerText.length == 1) { // prevent that first paragraph gets deleted
                    e.preventDefault();

                    return false;
                }
            }
            else if(e.which == M && e.ctrlKey) { // TODO: what is Ctrl + M actually good for?
                e.preventDefault(); // but be aware in this way also (JavaFX) application won't be able to use Ctrl + M

                return false;
            }
        });

        this._textField.addEventListener("keyup", function(e) {
            if(e.altKey || e.ctrlKey) { // some key combinations activate commands like CTRL + B setBold() -> update editor state so that UI is aware of this
                editor._updateEditorState();
            }
        });

        this._textField.addEventListener("input", function(){ editor._scheduleHeightNotification(); });
        this._textField.addEventListener("cut", function(){ editor._scheduleHeightNotification(); });
        this._textField.addEventListener("paste", function(e) { editor._handlePaste(e); editor._scheduleHeightNotification(); });

        this._ensureEditorInsertsParagraphWhenPressingEnter();
        this._initDragImageToResize();
        this._updateEditorState();
        this._scheduleHeightNotification(true);

        // Attach image click to preview overlay (delegated on editor container)
        var overlay = document.getElementById('preview-overlay');
        var overlayImg = document.getElementById('preview-image');
        if (overlay && overlayImg) {
            overlay.addEventListener('click', function(){ overlay.style.display = 'none'; overlayImg.src=''; });
            this._textField.addEventListener('click', function(e){
                var t = e.target;
                if (t && t.tagName && t.tagName.toLowerCase() === 'img') {
                    overlayImg.src = t.src;
                    overlay.style.display = 'flex';
                }
            });
        }


        try {

          var mutationObserver = new MutationObserver(function(mutations){

            var shouldNotifyHeight = false;

            mutations.forEach(function(m){

              if (m.type === 'childList') {

                if ((m.addedNodes && m.addedNodes.length) || (m.removedNodes && m.removedNodes.length)) {

                  shouldNotifyHeight = true;

                }

                if (m.addedNodes && m.addedNodes.length) {

                  for (var i = 0; i < m.addedNodes.length; i++) {

                    var node = m.addedNodes[i];

                    if (node.tagName && node.tagName.toLowerCase() === 'img') {

                      if (editor._isImageResizingEnabled) {

                        editor._prepareImageForEditing(node);

                      } else {

                        editor._ensureImageLoadListener(node);

                      }

                    } else if (node.querySelectorAll) {

                      var nested = node.querySelectorAll('img');

                      for (var j = 0; j < nested.length; j++) {

                        if (editor._isImageResizingEnabled) {

                          editor._prepareImageForEditing(nested[j]);

                        } else {

                          editor._ensureImageLoadListener(nested[j]);

                        }

                      }

                    }

                  }

                }

              } else if (m.type === 'attributes' && m.target && m.target.tagName && m.target.tagName.toLowerCase() === 'img') {

                shouldNotifyHeight = true;

              }

            });

            if (shouldNotifyHeight) {

              editor._scheduleHeightNotification();

            }

          });

          mutationObserver.observe(this._textField, { childList: true, subtree: true, attributes: true });

        } catch(e) {}


        // Bubble scroll to Flutter when reaching top/bottom edges
        try {
          var el = this._textField;
          function atTop() { return el.scrollTop <= 0; }
          function atBottom() { return Math.ceil(el.scrollTop + el.clientHeight) >= el.scrollHeight; }

          // Mouse/touchpad wheel
          el.addEventListener('wheel', function(e){
            var dy = e.deltaY || 0;
            if ((dy < 0 && atTop()) || (dy > 0 && atBottom())) {
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('edgeScroll', dy);
              }
            }
          }, { passive: true });

          // Touch drag
          var touchStartY = 0;
          el.addEventListener('touchstart', function(e){
            if (e.touches && e.touches.length) touchStartY = e.touches[0].clientY || 0;
          }, { passive: true });
          el.addEventListener('touchmove', function(e){
            if (!(e.touches && e.touches.length)) return;
            var currentY = e.touches[0].clientY || 0;
            var dy = (touchStartY - currentY); // >0 means scrolling down
            var up = dy < 0, down = dy > 0;
            if ((up && atTop()) || (down && atBottom())) {
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('edgeScroll', dy);
              }
            }
          }, { passive: true });
        } catch(_) {}
    },

    _ensureEditorInsertsParagraphWhenPressingEnter: function() {
        // see https://stackoverflow.com/a/36373967
        this._executeCommand("DefaultParagraphSeparator", "p");

        this._textField.innerHTML = ""; // clear previous content

        var newElement = document.createElement("p");
        newElement.innerHTML = "&#8203";
        this._textField.appendChild(newElement);

        var selection=document.getSelection();
        var range=document.createRange();
        range.setStart(newElement.firstChild, 1);
        selection.removeAllRanges();
        selection.addRange(range);
    },

    _initDragImageToResize: function() {
        var angle = 0;

        interact.addDocument(window.document, {
          events: { passive: false },
        });

        interact('img.' + resizableImageClass)
        .draggable({
            onmove: window.dragMoveListener,
            restrict: {
                restriction: 'parent',
                elementRect: { top: 0, left: 0, bottom: 1, right: 1 }
            },
        })
        .resizable({
            // resize from right or bottom
            edges: { top: true, left: true, right: true, bottom: true},

           // keep the edges inside the parent
            restrictEdges: {
                outer: 'parent',
                endOnly: true,
            },

            // minimum size
            restrictSize: {
                min: { width: this._imageMinWidth, height: this._imageMinHeight },
            },

            inertia: true,
            preserveAspectRatio: true,
        })
        .gesturable({
            onmove: function (event) {

                var target = event.target;

                angle += event.da;

                if(Math.abs(90 - (angle % 360)) < 10){ angle = 90;}
                if(Math.abs(180 - (angle % 360)) < 10){ angle = 180;}
                if(Math.abs(270 - (angle % 360)) < 10){ angle = 270;}
                if(Math.abs(angle % 360) < 10){ angle = 0;}

                target.style.webkitTransform =
                target.style.transform =
                'rotate(' + angle + 'deg)';

            }
        })
        .on('resizemove', function (event) {

            var target = event.target,
                x = (parseFloat(target.getAttribute('data-x')) || 0),
                y = (parseFloat(target.getAttribute('data-y')) || 0);

            // update the element's style
            var widthValue = Math.max(event.rect.width, editor._imageMinWidth);
            var heightValue = Math.max(event.rect.height, editor._imageMinHeight);
            var widthPx = widthValue + 'px';
            var heightPx = heightValue + 'px';
            target.style.width  = widthPx;
            target.style.height = heightPx;

            target.removeAttribute('width');
            target.removeAttribute('height');

            target.setAttribute('data-width', Math.round(widthValue));
            target.setAttribute('data-height', Math.round(heightValue));

            var parent = target.parentElement;
            if (parent && parent.classList && parent.classList.contains('editor-image-wrapper')) {
                parent.style.width = widthPx;
                parent.style.height = heightPx;
            }

            target.setAttribute('data-x', x);
            target.setAttribute('data-y', y);

            editor._applyWrapperDimensions(target);
            editor._scheduleHeightNotification();

        });
    },


    _handleTextEntered: function() {
        if(this._getHtml() == "<p><br></p>") { // SwiftKey, when deleting all entered text, inserts a pure "<br>" therefore check for <p>​&#8203</p> doesn't work anymore
            this._ensureEditorInsertsParagraphWhenPressingEnter();
        }

        this._updateEditorState();
    },

    _handlePaste: function(event) {
        var clipboardData = event.clipboardData || window.clipboardData;
        var pastedData = clipboardData.getData('text/html') || clipboardData.getData('text').replace(/(?:\r\n|\r|\n)/g, '<br />'); // replace new lines // TODO: may use 'text/plain' instead of 'text'

        this._waitTillPastedDataInserted(event, pastedData);
    },

    _waitTillPastedDataInserted: function(event, pastedData) {
        var previousHtml = this._getHtml();

        setTimeout(function () { // on paste event inserted text is not inserted yet -> wait for till text has been inserted
            editor._waitTillPastedTextInserted(previousHtml, 10, pastedData); // max 10 tries, after that we give up to prevent endless loops
        }, 100);
    },

    _waitTillPastedTextInserted: function(previousHtml, iteration, pastedData) {
        var hasBeenInserted = this._getHtml() != previousHtml;

        if(hasBeenInserted || ! iteration) {
            // there seems to be a bug (on Linux only?) when pasting data e.g. from Firefox: then only '' gets inserted
            if((this._getHtml().indexOf('​ÿþ&lt;') !== -1 || this._getHtml().indexOf('ÿþ&lt;<br>') !== -1) && previousHtml.indexOf('​​ÿþ&lt;') === -1) {
                this._textField.innerHTML = this._getHtml().replace('​ÿþ&lt;', pastedData).replace('ÿþ&lt;<br>', pastedData);
                // TODO: set caret to end of pasted data
            }

            this._updateEditorState();
            this._scheduleHeightNotification();
        }
        else {
            setTimeout(function () { // wait for till pasted data has been inserted
                editor._waitTillPastedTextInserted(pastedText, iteration - 1);
            }, 100);
        }
    },


    _getHtml: function() {
        return this._textField.innerHTML;
    },

    _getHtmlWithoutInternalModifications: function() {
        var clonedHtml = this._textField.cloneNode(true);
        var originalImages = this._textField.getElementsByTagName('img');
        var clonedImages = clonedHtml.getElementsByTagName('img');

        for (var i = 0; i < clonedImages.length; i++) {
            var originalImage = originalImages[i];
            var clonedImage = clonedImages[i];

            if (originalImage) {
                var rect = originalImage.getBoundingClientRect();
                var computedWidth = rect.width || originalImage.naturalWidth;
                var computedHeight = rect.height || originalImage.naturalHeight;

                if (computedWidth) {
                    clonedImage.style.width = computedWidth + 'px';
                    clonedImage.setAttribute('width', computedWidth);
                }

                if (computedHeight) {
                    clonedImage.style.height = computedHeight + 'px';
                    clonedImage.setAttribute('height', computedHeight);
                }
            }

            var storedWidth = clonedImage.getAttribute('data-width');
            var storedHeight = clonedImage.getAttribute('data-height');

            if (!storedWidth && clonedImage.hasAttribute('width')) {
                storedWidth = clonedImage.getAttribute('width');
            }
            if (!storedHeight && clonedImage.hasAttribute('height')) {
                storedHeight = clonedImage.getAttribute('height');
            }

            clonedImage.removeAttribute('width');
            clonedImage.removeAttribute('height');

            if (storedWidth) {
                clonedImage.setAttribute('data-width', storedWidth);
            }
            if (storedHeight) {
                clonedImage.setAttribute('data-height', storedHeight);
            }

            this._removeClass(clonedImage, resizableImageClass);
            this._removeClass(clonedImage, 'editor-small');
        }

        return clonedHtml.innerHTML;
    },

    getEncodedHtml: function() {
        return encodeURIComponent(this._getHtmlWithoutInternalModifications());
    },

    setHtml: function(html, baseUrl) {
        if(baseUrl) {
            this._setBaseUrl(baseUrl);
        }

        if(html.length != 0) {
            var decodedHtml = this._decodeHtml(html);
            this._textField.innerHTML = decodedHtml;

            this._htmlSetByApplication = decodedHtml;

            if(this._isImageResizingEnabled) {
                this.makeImagesResizeable();
            }
        }
        else {
            this._ensureEditorInsertsParagraphWhenPressingEnter();

            this._htmlSetByApplication = null;
        }

        this.didHtmlChange = false;

        this._scheduleHeightNotification(true);
    },

    _decodeHtml: function(html) {
        // We ensure the Dart side passes encodeURIComponent(html)
        // so a plain decodeURIComponent here is sufficient and
        // does not corrupt '+' characters in base64 data URIs.
        return decodeURIComponent(html);
    },

    _setBaseUrl: function(baseUrl) {
        var baseElements = document.head.getElementsByTagName('base');
        var baseElement = null;
        if(baseElements.length > 0) {
            baseElement = baseElements[0];
        }
        else {
            var baseElement = document.createElement('base');
            document.head.appendChild(baseElement); // don't know why but append() is not available
        }

        baseElement.setAttribute('href', baseUrl);
        baseElement.setAttribute('target', '_blank');
    },

    useWindowLocationForEditorStateChangedCallback: function() {
        this._useWindowLocationForEditorStateChangedCallback = true;
    },

    makeImagesResizeable: function() {
        this._isImageResizingEnabled = true;

        var images = document.getElementsByTagName("img");

        for(var i = 0; i < images.length; i++) {
            this._prepareImageForEditing(images[i]);
        }
    },

    disableImageResizing: function() {
        this._isImageResizingEnabled = false;

        this._removeResizeImageClasses(document);
    },

    _prepareImageForEditing: function(image) {
        if (!image) {
            return;
        }

        this._addClass(image, resizableImageClass);

        var wrapper = this._ensureImageWrapper(image);
        this._ensureResizeHandle(wrapper);
        this._ensureImageLoadListener(image);

        if (!image.getAttribute('data-width')) {
            var attrWidth = image.getAttribute('width');
            if (attrWidth) {
                image.setAttribute('data-width', attrWidth);
            }
        }

        if (!image.getAttribute('data-height')) {
            var attrHeight = image.getAttribute('height');
            if (attrHeight) {
                image.setAttribute('data-height', attrHeight);
            }
        }

        if (image.complete) {
            this._applyWrapperDimensions(image);
        } else {
            image.removeAttribute('width');
            image.removeAttribute('height');
        }
    },

    _ensureImageWrapper: function(image) {
        if (!image || !image.parentElement) {
            return null;
        }

        var parent = image.parentElement;
        if (parent.classList && parent.classList.contains('editor-image-wrapper')) {
            return parent;
        }

        var wrapper = document.createElement('span');
        wrapper.className = 'editor-image-wrapper';
        wrapper.style.display = 'inline-block';
        wrapper.style.position = 'relative';

        parent.insertBefore(wrapper, image);
        wrapper.appendChild(image);

        return wrapper;
    },

    _ensureResizeHandle: function(wrapper) {
        if (!wrapper) {
            return;
        }

        if (!wrapper.querySelector('.editor-resize-handle--bottom-right')) {
            var br = document.createElement('span');
            br.className = 'editor-resize-handle editor-resize-handle--bottom-right';
            wrapper.appendChild(br);
        }

        if (!wrapper.querySelector('.editor-resize-handle--top-right')) {
            var tr = document.createElement('span');
            tr.className = 'editor-resize-handle editor-resize-handle--top-right';
            wrapper.appendChild(tr);
        }
    },

    _applyWrapperDimensions: function(image) {
        if (!image) {
            return;
        }

        var wrapper = image.parentElement;
        if (!wrapper || !wrapper.classList || !wrapper.classList.contains('editor-image-wrapper')) {
            return;
        }

        var resolvedWidth = parseFloat(image.getAttribute('data-width'));
        if (!resolvedWidth || isNaN(resolvedWidth) || resolvedWidth <= 0) {
            var measuredWidth = image.offsetWidth || image.naturalWidth;
            if (measuredWidth && measuredWidth > 0) {
                resolvedWidth = measuredWidth;
                image.setAttribute('data-width', Math.round(resolvedWidth));
            } else {
                resolvedWidth = null;
            }
        }

        var resolvedHeight = parseFloat(image.getAttribute('data-height'));
        if (!resolvedHeight || isNaN(resolvedHeight) || resolvedHeight <= 0) {
            var measuredHeight = image.offsetHeight || image.naturalHeight;
            if (measuredHeight && measuredHeight > 0) {
                resolvedHeight = measuredHeight;
                image.setAttribute('data-height', Math.round(resolvedHeight));
            } else {
                resolvedHeight = null;
            }
        }

        if (resolvedWidth) {
            wrapper.style.width = resolvedWidth + 'px';
            image.style.width = resolvedWidth + 'px';
        } else {
            wrapper.style.width = '';
            image.style.width = '';
        }

        if (resolvedHeight) {
            wrapper.style.height = resolvedHeight + 'px';
            image.style.height = resolvedHeight + 'px';
        } else {
            wrapper.style.height = '';
            image.style.height = '';
        }

        if (resolvedWidth || resolvedHeight) {
            image.removeAttribute('width');
            image.removeAttribute('height');
        }
    },

    _ensureImageLoadListener: function(image) {
        if (!image || image._editorResizeLoadListenerAttached) {
            return;
        }

        image.addEventListener('load', function() {
            editor._applyWrapperDimensions(image);
            editor._scheduleHeightNotification();
        });

        image._editorResizeLoadListenerAttached = true;
    },

    _removeResizeImageClasses: function(document) {
        var images = document.getElementsByTagName("img");

        for(var i = 0; i < images.length; i++) {
            var img = images[i];
            this._removeClass(img, resizableImageClass);
            // also strip editor-only visual class before exporting html
            this._removeClass(img, 'editor-small');

            var parent = img.parentElement;
            if (parent && parent.classList && parent.classList.contains('editor-image-wrapper')) {
                var handles = parent.querySelectorAll('.editor-resize-handle');
                handles.forEach(function(handle){ parent.removeChild(handle); });

                if (parent.parentNode) {
                    parent.parentNode.insertBefore(img, parent);
                    parent.parentNode.removeChild(parent);
                }
            }
        }
    },

    _scheduleHeightNotification: function(force) {
        if (force) {
            this._forceHeightNotification = true;
        }

        if (this._heightNotifyScheduled) {
            return;
        }

        var editorRef = this;
        this._heightNotifyScheduled = true;

        var dispatcher = window.requestAnimationFrame || function(cb) { return setTimeout(cb, 16); };

        dispatcher(function() {
            editorRef._heightNotifyScheduled = false;
            var shouldForce = editorRef._forceHeightNotification || force;
            editorRef._forceHeightNotification = false;
            editorRef._notifyHeightIfNeeded(shouldForce);
        });
    },

    _notifyHeightIfNeeded: function(force) {
        if (!this._textField) {
            return;
        }

        var scrollHeight = this._textField.scrollHeight || 0;
        var offsetHeight = this._textField.offsetHeight || 0;
        var height = Math.max(scrollHeight, offsetHeight);

        if (!force && Math.abs(height - this._lastKnownHeight) < 1) {
            return;
        }

        this._lastKnownHeight = height;

        try {
            if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('contentHeight', height);
            } else if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.contentHeight) {
                window.webkit.messageHandlers.contentHeight.postMessage(height);
            } else if (window.parent && window.parent !== window && window.parent.postMessage) {
                window.parent.postMessage({ type: 'contentHeight', height: height }, '*');
            }
        } catch (e) {
            console.log('Height notification failed', e);
        }
    },

    refreshHeight: function() {
        this._notifyHeightIfNeeded(true);
    },

    _hasClass: function(element, className) {
      return !!element.className.match(new RegExp('(\\s|^)' + className +'(\\s|$)'));
    },

    _addClass: function(element, className) {
      if (this._hasClass(element, className) == false) {
        element.className += " " + className;
      }
    },

    _removeClass: function(element, className) {
      if (this._hasClass(element, className)) {
        element.classList.remove(className);

        var classAttributeValue = element.getAttribute('class');
        if (!!! classAttributeValue) { // remove class attribute if no class is left to restore original html
            element.removeAttribute('class');
        }
      }
    },
    
    
    /*      Text Commands        */

    undo: function() {
        this._executeCommand('undo', null);
    },
    
    redo: function() {
        this._executeCommand('redo', null);
    },
    
    setBold: function() {
        this._executeCommand('bold', null);
    },
    
    setItalic: function() {
        this._executeCommand('italic', null);
    },

    setUnderline: function() {
        this._executeCommand('underline', null);
    },
    
    setSubscript: function() {
        this._executeCommand('subscript', null);
    },
    
    setSuperscript: function() {
        this._executeCommand('superscript', null);
    },
    
    setStrikeThrough: function() {
        this._executeCommand('strikeThrough', null);
    },

    setTextColor: function(color) {
        this._executeStyleCommand('foreColor', color);
    },

    setTextBackgroundColor: function(color) {
        if(color == 'rgba(0, 0, 0, 0)') { // resetting backColor does not work with any color value (whether #00000000 nor rgba(0, 0, 0, 0)), we have to pass 'inherit'. Thanks to https://stackoverflow.com/a/7071465 for pointing this out to me
            this._executeStyleCommand('backColor', 'inherit');
        }
        else {
            this._executeStyleCommand('backColor', color);
        }
    },

    setFontName: function(fontName) {
        this._executeCommand("fontName", fontName);
    },

    setFontSize: function(fontSize) {
        this._executeCommand("fontSize", fontSize);
    },

    setHeading: function(heading) {
        this._executeCommand('formatBlock', '<h'+heading+'>');
    },

    setFormattingToParagraph: function() {
        this._executeCommand('formatBlock', '<p>');
    },

    setPreformat: function() {
        this._executeCommand('formatBlock', '<pre>');
    },

    setBlockQuote: function() {
        this._executeCommand('formatBlock', '<blockquote>');
    },

    removeFormat: function() {
        this._executeCommand('removeFormat', null);
    },
    
    setJustifyLeft: function() {
        this._executeCommand('justifyLeft', null);
    },
    
    setJustifyCenter: function() {
        this._executeCommand('justifyCenter', null);
    },
    
    setJustifyRight: function() {
        this._executeCommand('justifyRight', null);
    },

    setJustifyFull: function() {
        this._executeCommand('justifyFull', null);
    },

    setIndent: function() {
        this._executeCommand('indent', null);
    },

    setOutdent: function() {
        this._executeCommand('outdent', null);
    },

    insertBulletList: function() {
        this._executeCommand('insertUnorderedList', null);
    },

    insertNumberedList: function() {
        this._executeCommand('insertOrderedList', null);
    },


    /*      Insert elements             */

    insertLink: function(url, title) {
        this._restoreRange();
        var sel = document.getSelection();

        if (sel.toString().length == 0) {
            this._insertHtml("<a href='"+url+"'>"+title+"</a>");
        }
        else if (sel.rangeCount) {
           var el = document.createElement("a");
           el.setAttribute("href", url);
           el.setAttribute("title", title);

           var range = sel.getRangeAt(0).cloneRange();
           range.surroundContents(el);
           sel.removeAllRanges();
           sel.addRange(range);

           this._updateEditorState();
       }
    },

    insertImage: function(url, alt, width, height, rotation) {
        var imageElement = document.createElement('img');

        imageElement.setAttribute('src', url);

        if(alt) {
            imageElement.setAttribute('alt', alt);
        }

        if(width)  {
            imageElement.setAttribute('data-width', width);
        }

        if(height)  {
            imageElement.setAttribute('data-height', height);
        }

        if(this._isImageResizingEnabled) {
            imageElement.setAttribute('class', (imageElement.getAttribute('class') || '').trim() + ' ' + resizableImageClass);
        }

        if(rotation)  {
            this._setImageRotation(imageElement, rotation);
        }

        // insert as temporary wrapper so we can regrab the created element
        var wrapper = document.createElement('div');
        wrapper.innerHTML = imageElement.outerHTML;
        var inserted = wrapper.firstChild;

        if (this._isImageResizingEnabled) {
            var targetWidth = inserted.getAttribute('data-width');
            if (!targetWidth) {
                var containerWidth = this._textField.clientWidth || window.innerWidth || 0;
                targetWidth = Math.round(containerWidth * 0.75);
                inserted.setAttribute('data-width', targetWidth);
            }

            inserted.style.width = targetWidth + 'px';
            inserted.removeAttribute('width');
        }

        this._insertHtml(inserted.outerHTML);

        this._scheduleHeightNotification();
    },

    _setImageRotation: function(imageElement, rotation) {
            if(rotation == 90) {
                this._addClass(imageElement, 'rotate90deg');
            }
            else if(rotation == 180) {
                this._addClass(imageElement, 'rotate180deg');
            }
            else if(rotation == 270) {
                this._addClass(imageElement, 'rotate270deg');
            }
    },

    insertVideo: function(url, width, height, fromDevice) {
    console.log(url);
        if (fromDevice) {
            this._insertVideo(url, width, height);
        } else {
            this._insertYoutubeVideo(url, width, height);
        }
    },
    
    _insertYoutubeVideo: function(url, width, height) {
        var html = '<iframe width="'+ width +'" height="'+ height +'" src="' + url + '" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"></iframe>';
        this._insertHtml(html);
    },

    _insertVideo: function(url, width, height) {
        var html = '<video width="'+ width +'" height="'+ height +'" controls><source type="video/mp4" src="'+ url +'"></video>'
        this._insertHtml(html);
    },

    insertCheckbox: function(text) {
        var editor = this;

        var html = '<input type="checkbox" name="'+ text +'" value="'+ text +'" onclick="editor._checkboxClicked(this)"/> &nbsp;';
        this._insertHtml(html);
    },

    _checkboxClicked: function(clickedCheckbox) {
        // incredible, checked attribute doesn't get set in html, see issue https://github.com/dankito/RichTextEditor/issues/24
        if (clickedCheckbox.checked) {
            clickedCheckbox.setAttribute('checked', 'checked');
        }
        else {
            clickedCheckbox.removeAttribute('checked');
        }

        this._updateEditorState();
    },

    insertHtml: function(encodedHtml) {
        var html = this._decodeHtml(encodedHtml);
        this._insertHtml(html);
    },

    _insertHtml: function(html) {
        this._backupRange();
        this._restoreRange();

        document.execCommand('insertHTML', false, html);

        if(this._isImageResizingEnabled) {
            this.makeImagesResizeable();
        }

        this._updateEditorState();
    },
    
    
    /*      Editor default settings     */
    
    setBaseTextColor: function(color) {
        this._textField.style.color  = color;
    },

    setBaseFontFamily: function(fontFamily) {
        this._textField.style.fontFamily = fontFamily;
    },
    
    setBaseFontSize: function(size) {
        this._textField.style.fontSize = size;
    },
    
    setPadding: function(left, top, right, bottom) {
      this._textField.style.paddingLeft = left;
      this._textField.style.paddingTop = top;
      this._textField.style.paddingRight = right;
      this._textField.style.paddingBottom = bottom;
    },

    // TODO: is this one ever user?
    setBackgroundColor: function(color) {
        document.body.style.backgroundColor = color;
    },
    
    setBackgroundImage: function(image) {
        this._textField.style.backgroundImage = image;
    },
    
    setWidth: function(size) {
        this._textField.style.minWidth = size; // TODO: why did i use minWidth here but height (not minHeight) below?
    },
    
    setHeight: function(size) {
        this._textField.style.height = size;
    },
    
    setTextAlign: function(align) {
        this._textField.style.textAlign = align;
    },
    
    setVerticalAlign: function(align) {
        this._textField.style.verticalAlign = align;
    },
    
    setPlaceholder: function(placeholder) {
        this._textField.setAttribute("placeholder", placeholder);
    },
    
    setInputEnabled: function(inputEnabled) {
        this._textField.contentEditable = String(inputEnabled);

        if(inputEnabled) { // TODO: may interferes with _isImageResizingEnabled
            this.makeImagesResizeable();
        }
        else {
            this.disableImageResizing();
        }
    },

    focus: function() {
        var range = document.createRange();
        range.selectNodeContents(this._textField);
        range.collapse(false);
        var selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        this._textField.focus();
    },

    blurFocus: function() {
        this._textField.blur();
    },


    _executeStyleCommand: function(command, parameter) {
        this._executeCommand("styleWithCSS", null, true);
        this._executeCommand(command, parameter);
        this._executeCommand("styleWithCSS", null, false);
    },

    _executeCommand: function(command, parameter) {
        document.execCommand(command, false, parameter);

        this._updateEditorState();
    },


    _updateEditorState: function() {
        var html = this._getHtmlWithoutInternalModifications();
        var didHtmlChange = (this._htmlSetByApplication != null && this._htmlSetByApplication != html) || // html set by application changed
                            (this._htmlSetByApplication == null && html != EditorDefaultHtml); // or if html not set by application: default html changed

        if (typeof editorCallback !== 'undefined') { // in most applications like in the JavaFX app changing window.location.href doesn't work -> tell them via callback that editor state changed
            editorCallback.updateEditorState(didHtmlChange) // these applications determine editor state manually
        }
        else if (this._useWindowLocationForEditorStateChangedCallback) { // Android can handle changes to windows.location -> communicate editor changes via a self defined protocol name
            var commandStates = this._determineCommandStates();

            var editorState = {
                'didHtmlChange': didHtmlChange,
                'html': html, // TODO: remove in upcoming versions
                'commandStates': commandStates
            };

            window.location.href = "editor-state-changed-callback://" + encodeURIComponent(JSON.stringify(editorState));
        }
    },

    _determineCommandStates: function() {
        var commandStates = {};

        this._determineStateForCommand('undo', commandStates);
        this._determineStateForCommand('redo', commandStates);

        this._determineStateForCommand('bold', commandStates);
        this._determineStateForCommand('italic', commandStates);
        this._determineStateForCommand('underline', commandStates);
        this._determineStateForCommand('subscript', commandStates);
        this._determineStateForCommand('superscript', commandStates);
        this._determineStateForCommand('strikeThrough', commandStates);

        this._determineStateForCommand('foreColor', commandStates);
        this._determineStateForCommand('backColor', commandStates);

        this._determineStateForCommand('fontName', commandStates);
        this._determineStateForCommand('fontSize', commandStates);

        this._determineStateForCommand('formatBlock', commandStates);
        this._determineStateForCommand('removeFormat', commandStates);

        this._determineStateForCommand('justifyLeft', commandStates);
        this._determineStateForCommand('justifyCenter', commandStates);
        this._determineStateForCommand('justifyRight', commandStates);
        this._determineStateForCommand('justifyFull', commandStates);

        this._determineStateForCommand('indent', commandStates);
        this._determineStateForCommand('outdent', commandStates);

        this._determineStateForCommand('insertUnorderedList', commandStates);
        this._determineStateForCommand('insertOrderedList', commandStates);
        this._determineStateForCommand('insertHorizontalRule', commandStates);
        this._determineStateForCommand('insertHTML', commandStates);

        return commandStates;
    },

    _determineStateForCommand: function(command, commandStates) {
        commandStates[command.toUpperCase()] = {
            'executable': document.queryCommandEnabled(command),
            'value': document.queryCommandValue(command)
        }
    },


    _backupRange: function(){
        var selection = window.getSelection();
        if(selection.rangeCount > 0) {
          var range = selection.getRangeAt(0);

          this._currentSelection = {
              "startContainer": range.startContainer,
              "startOffset": range.startOffset,
              "endContainer": range.endContainer,
              "endOffset": range.endOffset
          };
        }
    },

    _restoreRange: function(){
        var selection = window.getSelection();
        selection.removeAllRanges();

        var range = document.createRange();
        range.setStart(this._currentSelection.startContainer, this._currentSelection.startOffset);
        range.setEnd(this._currentSelection.endContainer, this._currentSelection.endOffset);

        selection.addRange(range);
    },

}


editor.init();
