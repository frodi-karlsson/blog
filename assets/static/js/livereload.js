(function() {
  const socket = new EventSource("/live-reload");

  socket.onmessage = function(event) {
    const data = JSON.parse(event.data);

    if (data.type === "full") {
      location.reload();
      return;
    }

    if (data.type === "css") {
      const links = document.querySelectorAll("link[rel='stylesheet']");
      links.forEach(link => {
        const url = new URL(link.href);
        url.searchParams.set("v", Date.now());
        link.href = url.href;
      });
    }
  };

  socket.onerror = function() {
    console.log("LiveReload connection lost. Retrying...");
  };
})();
